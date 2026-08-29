# Evaluate the system-manager integration. The important boundary is that the
# compositor descriptor points at cscroll while pacman only receives optional
# wlroots companions.
{ pkgs, lib ? pkgs.lib, systemManagerModule }:
let
  fakeCscroll = pkgs.writeShellScriptBin "scroll" "exit 0";

  stubs = { lib, ... }: {
    options = {
      nixarch.packages = {
        pacman = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
        aur = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
      };
      nixdesktop.launcher.compositors = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      environment.etc = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            text = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            replaceExisting = lib.mkOption { type = lib.types.bool; default = false; };
          };
        });
      };
    };
  };

  evaluateAll = extraConfig: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      stubs
      systemManagerModule
      { nixscroll.install.package = fakeCscroll; }
      extraConfig
    ];
  }).config;

  packagesOf = extraConfig: (evaluateAll extraConfig).nixarch.packages;
  etcOf = extraConfig: (evaluateAll extraConfig).environment.etc;

  base = evaluateAll { };
  descriptor = base.nixdesktop.launcher.compositors.scroll;
  nothing = packagesOf { };
  companions = packagesOf {
    nixscroll.install = {
      wallpaper.enable = true;
      outputControl.enable = true;
      portal.enable = true;
    };
  };
  portalPath = "xdg-desktop-portal/scroll-portals.conf";
  portalEtc = etcOf { nixscroll.install.portal.enable = true; };
  portalConf = portalEtc.${portalPath} or null;
  sorted = lib.sort (a: b: a < b);

  results = {
    "the compositor descriptor uses the selected cscroll derivation" =
      toString descriptor.package == toString fakeCscroll
      && descriptor.command == "scroll";
    "the descriptor carries Scroll's compositor mechanisms" =
      descriptor.env == [ "WLR_DRM_DEVICES" ]
      && descriptor.supportsVirtualOutputs
      && !descriptor.supportsNotify
      && descriptor.currentDesktop == "scroll";

    "cscroll is never mirrored into pacman or the AUR" =
      nothing.pacman == [ ] && nothing.aur == [ ];
    "all optional companions use the Arch repository plane" =
      sorted companions.pacman
      == [ "swaybg" "wlr-randr" "xdg-desktop-portal-wlr" ]
      && companions.aur == [ ];
    "each companion remains an independent choice" =
      (packagesOf { nixscroll.install.wallpaper.enable = true; }).pacman == [ "swaybg" ]
      && (packagesOf { nixscroll.install.outputControl.enable = true; }).pacman == [ "wlr-randr" ];

    "portal enable installs its wlroots backend" =
      (packagesOf { nixscroll.install.portal.enable = true; }).pacman
      == [ "xdg-desktop-portal-wlr" ];
    "portal routing is desktop-specific rather than global" =
      lib.attrNames portalEtc == [ portalPath ]
      && !(portalEtc ? "xdg-desktop-portal/portals.conf");
    "the portal file cannot be silently skipped" =
      portalConf != null && portalConf.replaceExisting;
    "the portal file selects wlr capture and a general fallback" =
      portalConf != null
      && lib.hasInfix "\ndefault=gtk\n" "\n${portalConf.text}"
      && lib.hasInfix "\norg.freedesktop.impl.portal.ScreenCast=wlr\n" portalConf.text
      && lib.hasInfix "\norg.freedesktop.impl.portal.Screenshot=wlr\n" portalConf.text;
    "the portal fallback remains configurable" =
      let
        kde = (etcOf {
          nixscroll.install.portal = { enable = true; fallback = "kde"; };
        }).${portalPath} or null;
      in
      kde != null
      && lib.hasInfix "\ndefault=kde\n" "\n${kde.text}"
      && !(lib.hasInfix "default=gtk" kde.text);
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixscroll: the Arch cscroll integration is broken. Failing assertions:
    ${lib.concatMapStringsSep "\n" (failure: "  - ${failure}") failed}
  ''
