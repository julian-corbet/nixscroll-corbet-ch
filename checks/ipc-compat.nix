# Evaluates home/ipc-compat.nix for real and asserts the proxy it generates.
#
# WHY THIS FILE EXISTS AT ALL, same reasoning as checks/startup-contract.nix: `nix flake check`
# does not evaluate `homeManagerModules`. It reports them as "unchecked" and moves on.
#
# WHAT IS ACTUALLY AT RISK HERE. This module writes a program as text, so nothing type-checks it —
# and its two most consequential values are ones a consumer never sees fail:
#
#   · THE SHEBANG. Wrong interpreter path and the unit fails with `203/EXEC`, which reads like a
#     missing binary rather than a missing Python.
#   · `unsetVariables`. Its whole purpose is that pointing SWAYSOCK at the proxy is INERT while
#     scroll's own SCROLLSOCK is still set. If this list ever came back empty, every consumer would
#     go on connecting straight to the compositor and the shim would appear to be running fine.
#     Nothing anywhere would report it.
#
# And one structural risk: `favorites` gates two of the three rewrites, so an empty list must still
# produce a working layout-rewriting proxy rather than a no-op.
{ pkgs, lib ? pkgs.lib }:
let
  stubs = { lib, ... }: {
    options = {
      xdg.configHome = lib.mkOption { type = lib.types.str; default = "/home/u/.config"; };
      xdg.configFile = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
      };
      home.packages = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      home.file = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      systemd.user = lib.mkOption { type = lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  evalWith = settings: (lib.evalModules {
    modules = [ stubs ../home/ipc-compat.nix { programs.scroll.ipcCompat = settings; } ];
  }).config;

  has = haystack: needle: lib.hasInfix needle haystack;

  pinned = evalWith { enable = true; favorites = [ 1 2 3 4 5 ]; };
  pinnedCfg = pinned.programs.scroll.ipcCompat;
  pinnedScript = pinned.xdg.configFile."scroll/scroll-swayipc-shim";
  pinnedUnit = pinned.systemd.user.services.scroll-ipc-compat;

  bare = evalWith { enable = true; };
  bareScript = bare.xdg.configFile."scroll/scroll-swayipc-shim".text;

  nixosStyle = evalWith {
    enable = true;
    interpreter = "/nix/store/deadbeef-python3-3.12.8/bin/python3";
  };

  noService = evalWith { enable = true; enableService = false; };
  off = evalWith { enable = false; favorites = [ 1 ]; };

  renamed = evalWith {
    enable = true;
    socketName = "compat.sock";
    serviceName = "scroll-shim";
  };
  renamedCfg = renamed.programs.scroll.ipcCompat;

  results = {
    # ── the script lands, executable, with a runnable shebang ─────────────────────────────────
    "the script is written under ~/.config/scroll" =
      pinned.xdg.configFile ? "scroll/scroll-swayipc-shim";
    "the script is executable — a unit cannot ExecStart a file without +x" =
      pinnedScript.executable == true;
    "the default shebang is the distro interpreter, not a store path" =
      lib.hasPrefix "#!/usr/bin/env python3\n" pinnedScript.text;
    "a NixOS consumer's absolute interpreter reaches the shebang verbatim" =
      lib.hasPrefix "#!/nix/store/deadbeef-python3-3.12.8/bin/python3\n"
        nixosStyle.xdg.configFile."scroll/scroll-swayipc-shim".text;

    # ── favorites: injected as a Python literal, and gating two of the three rewrites ─────────
    "favorites reach the script as a Python list literal" =
      has pinnedScript.text "FAVOURITES = [1, 2, 3, 4, 5]";
    "no favorites renders an empty list, not a missing name" =
      has bareScript "FAVOURITES = []";
    "...and the layout rewrite still runs, so an empty list is not a no-op proxy" =
      has bareScript "b'\"layout\":\"splith\"'" && has bareScript "b'\"layout\":\"splitv\"'";

    # ── framing: the one way to get this badly wrong ──────────────────────────────────────────
    "every forwarded frame is re-headered from its own payload length" =
      has bareScript "struct.pack(\"<II\", len(payload), mtype)";

    # ── the socket name is used in BOTH places it appears ─────────────────────────────────────
    "socketPath uses systemd's %t specifier, valid in ExecStart= and Environment= alike" =
      pinnedCfg.socketPath == "%t/scroll-swaycompat.sock";
    "a renamed socket propagates to socketPath" =
      renamedCfg.socketPath == "%t/compat.sock";
    "...and to the script's own fallback, so the two cannot drift apart" =
      has renamed.xdg.configFile."scroll/scroll-swayipc-shim".text "\"compat.sock\"";

    # ── unsetVariables: the value whose absence would fail silently forever ───────────────────
    "unsetVariables names scroll's own socket variable" =
      lib.elem "SCROLLSOCK" pinnedCfg.unsetVariables;
    "unsetVariables names the i3 one too — a sway client probes both before SWAYSOCK" =
      lib.elem "I3SOCK" pinnedCfg.unsetVariables;
    "unsetVariables is never empty; an empty list is a silently bypassed proxy" =
      pinnedCfg.unsetVariables != [ ];
    "unsetVariables is read-only — it describes what scroll exports, not a preference" =
      !(builtins.tryEval (builtins.deepSeq
        (evalWith { enable = true; unsetVariables = [ ]; }) true)).success;

    # ── the unit ──────────────────────────────────────────────────────────────────────────────
    "the service is named by serviceName, which a consumer orders against" =
      renamed.systemd.user.services ? scroll-shim;
    "ExecStart is the published command, so `command` cannot describe a different unit" =
      pinnedUnit.Service.ExecStart == pinnedCfg.command;
    "...and that command names both the script and the socket" =
      has pinnedCfg.command "scroll/scroll-swayipc-shim"
      && has pinnedCfg.command "%t/scroll-swaycompat.sock";
    "Type=exec, so a missing interpreter fails the start instead of reporting success" =
      pinnedUnit.Service.Type == "exec";
    "it is bound to graphical-session.target, where SWAYSOCK actually exists" =
      pinnedUnit.Unit.Requisite == [ "graphical-session.target" ]
      && pinnedUnit.Install.WantedBy == [ "graphical-session.target" ];

    # ── the two off switches ──────────────────────────────────────────────────────────────────
    "enableService = false writes the script but declares no unit" =
      noService.xdg.configFile ? "scroll/scroll-swayipc-shim"
      && !(noService.systemd.user ? services);
    "disabled writes nothing at all, even with favorites set" =
      off.xdg.configFile == { } && !(off.systemd.user ? services);
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
# `pkgs.emptyFile` rather than a `runCommand` marker, for the reason spelled out at the bottom of
# checks/startup-contract.nix: a fixed-output path is byte-identical on every system, so
# `nix flake check --all-systems` substitutes it instead of trying to build an aarch64 marker on an
# x86_64 runner.
if failed == [ ]
then pkgs.emptyFile
else throw ''
  nixscroll: the sway-IPC compatibility proxy is broken. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
