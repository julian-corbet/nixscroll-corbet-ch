# Evaluate the IPC integration module for real. Runtime protocol behaviour is
# tested in cscroll; this check enforces the product boundary on the Nix side.
{ pkgs, ipcCompatModule, scrollPackage, lib ? pkgs.lib }:
let
  fakeCscroll = pkgs.writeShellScriptBin "scroll-swayipc-compat" "exit 0";

  stubs = { lib, ... }: {
    options = {
      xdg.configFile = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
      };
      systemd.user = lib.mkOption { type = lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  evalWith = settings: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      stubs
      ipcCompatModule
      { programs.scroll.ipcCompat = { package = fakeCscroll; } // settings; }
    ];
  }).config;

  enabled = evalWith { enable = true; };
  cfg = enabled.programs.scroll.ipcCompat;
  unit = enabled.systemd.user.services.scroll-ipc-compat;
  noService = evalWith { enable = true; enableService = false; };
  off = evalWith { enable = false; };
  renamed = evalWith {
    enable = true;
    socketName = "compat.sock";
    serviceName = "scroll-compat";
  };
  withFavorites = evalWith {
    enable = true;
    favorites = [ 1 2 2 5 ];
  };
  moduleSource = builtins.readFile ../home/ipc-compat.nix;
  flakeSource = builtins.readFile ../flake.nix;
  packageBuildCommand = builtins.unsafeDiscardStringContext (scrollPackage.buildCommand or "");
  pythonPath = builtins.unsafeDiscardStringContext (toString pkgs.python3);
  nativeBuildInputPaths = map
    (input: builtins.unsafeDiscardStringContext (toString input))
    (scrollPackage.nativeBuildInputs or [ ]);
  mesaEnvironment = scrollPackage.passthru.nixscrollMesaEnvironment or { };
  mesaPath = builtins.unsafeDiscardStringContext (toString pkgs.mesa);
  has = haystack: needle: lib.hasInfix needle haystack;

  results = {
    # The package owns the executable. Nix names it by absolute store path and
    # writes no second implementation under ~/.config.
    "the selected cscroll package provides the command path" =
      toString cfg.package == toString fakeCscroll
      && cfg.executable == "${fakeCscroll}/bin/scroll-swayipc-compat"
      && cfg.command == "${fakeCscroll}/bin/scroll-swayipc-compat %t/scroll-swaycompat.sock";
    "the executable path is read-only" =
      !(builtins.tryEval
        (evalWith { enable = true; executable = "/tmp/not-cscroll"; }).programs.scroll.ipcCompat.executable).success;
    "the module renders no proxy source file" = enabled.xdg.configFile == { };
    "the Nix module embeds no runtime implementation" =
      !(has moduleSource "shimSource")
      && !(has moduleSource "asyncio.start_unix_server")
      && !(has moduleSource "FAVOURITES =")
      && !(has moduleSource "def rewrite_layouts");
    "workspace favourites select cscroll's packaged policy" =
      withFavorites.programs.scroll.ipcCompat.favorites == [ 1 2 5 ]
      && withFavorites.programs.scroll.ipcCompat.command
      == "${fakeCscroll}/bin/scroll-swayipc-compat --favorite 1 --favorite 2 --favorite 5 %t/scroll-swaycompat.sock"
      && !(cfg ? interpreter);
    "workspace favourites must be positive" =
      !(builtins.tryEval
        (evalWith { enable = true; favorites = [ 0 ]; }).programs.scroll.ipcCompat.command).success;

    # The source follows are the package boundary. The outer build gate both
    # checks that cscroll installed the helper and makes its interpreter a
    # direct store reference without wrapping the compositor's runtime PATH.
    "both scroll-flake source slots follow the one cscroll input" =
      has flakeSource ''inputs.scroll-git.follows = "cscroll";''
      && has flakeSource ''inputs.scroll-stable.follows = "cscroll";'';
    "the committed cscroll input is remote and non-flake" =
      has flakeSource ''url = "github:corbet-labs/cscroll";''
      && has flakeSource "flake = false;"
      && !(has flakeSource "path:/home/");
    "Python is available only to patch the installed helper shebang" =
      lib.elem pythonPath nativeBuildInputPaths
      && has packageBuildCommand ''patchShebangs "$helper"''
      && has packageBuildCommand ''expected='#!${pythonPath}/bin/python3'';
    "package build fails closed when cscroll omits the helper" =
      has packageBuildCommand ''helper="$out/bin/scroll-swayipc-compat"''
      && has packageBuildCommand ''if [[ ! -x "$helper" ]]'';
    "the lndir helper is copied before its shebang is patched" =
      has packageBuildCommand ''if [[ -L "$helper" ]]''
      && has packageBuildCommand ''helperSource="$(readlink -f "$helper")"''
      && has packageBuildCommand ''cp "$helperSource" "$helper"'';
    "only scroll receives the portable Nix Mesa runtime environment" =
      builtins.unsafeDiscardStringContext (mesaEnvironment.eglVendor or "")
      == "${mesaPath}/share/glvnd/egl_vendor.d/50_mesa.json"
      && builtins.unsafeDiscardStringContext (mesaEnvironment.libglDrivers or "")
      == "${mesaPath}/lib/dri"
      && has flakeSource "extraSessionCommands = ''"
      && has flakeSource "export __EGL_VENDOR_LIBRARY_FILENAMES="
      && has flakeSource "export LIBGL_DRIVERS_PATH=";
    "the Mesa wrapper does not guess a hardware-specific Vulkan ICD" =
      !(has flakeSource "VK_ICD_FILENAMES");

    # Pointing SWAYSOCK at the proxy is silently bypassed unless the two
    # higher-priority compositor variables are absent in the client unit.
    "socketPath uses systemd's runtime-directory specifier" =
      cfg.socketPath == "%t/scroll-swaycompat.sock";
    "a renamed socket propagates into the command" =
      renamed.programs.scroll.ipcCompat.socketPath == "%t/compat.sock"
      && lib.hasSuffix " %t/compat.sock" renamed.programs.scroll.ipcCompat.command;
    "strict clients are told which bypass variables to unset" =
      cfg.unsetVariables == [ "SCROLLSOCK" "I3SOCK" ];
    "unsetVariables is read-only" =
      !(builtins.tryEval
        (evalWith { enable = true; unsetVariables = [ ]; }).programs.scroll.ipcCompat.unsetVariables).success;

    # Type=notify is a runtime contract implemented by cscroll. It makes a
    # dependent client's After= wait for the bound socket rather than execve().
    "the service name remains a consumer-readable option" =
      renamed.systemd.user.services ? scroll-compat;
    "the unit runs the published command" = unit.Service.ExecStart == cfg.command;
    "the unit waits for cscroll's readiness notification" = unit.Service.Type == "notify";
    "the unit documents cscroll's installed manual" =
      unit.Unit.Documentation == [ "man:scroll-swayipc-compat(1)" ];
    "the unit avoids the graphical-session ordering cycle" =
      unit.Unit.After == [ "graphical-session-pre.target" ]
      && unit.Unit.PartOf == [ "graphical-session.target" ]
      && unit.Install.WantedBy == [ "graphical-session.target" ];

    "enableService=false declares no unit and no generated program" =
      !(noService.systemd.user ? services) && noService.xdg.configFile == { };
    "disabled declares no unit and no generated program" =
      !(off.systemd.user ? services) && off.xdg.configFile == { };
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixscroll: the cscroll IPC integration boundary is broken. Failing assertions:
    ${lib.concatMapStringsSep "\n" (failure: "  - ${failure}") failed}
  ''
