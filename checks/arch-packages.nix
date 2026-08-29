# Evaluate the system-manager integration. The cscroll manifest is the only
# package list: enabling nixscroll registers the compositor, materializes every
# required external component, and installs the desktop-specific portal route.
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
      environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
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
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
      };
    };
  };

  evaluate = extraConfig: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      stubs
      systemManagerModule
      extraConfig
    ];
  }).config;

  enabled = evaluate {
    nixscroll = {
      enable = true;
      package = fakeCscroll;
    };
  };
  disabled = evaluate { };
  kde = evaluate {
    nixscroll = {
      enable = true;
      package = fakeCscroll;
      portalFallback = "kde";
    };
  };

  descriptor = enabled.nixdesktop.launcher.compositors.scroll;
  portalPath = "xdg-desktop-portal/scroll-portals.conf";
  portal = enabled.environment.etc.${portalPath};
  sorted = lib.sort (a: b: a < b);

  results = {
    "the compositor descriptor uses the selected cscroll derivation" =
      toString descriptor.package == toString fakeCscroll
      && descriptor.command == "scroll";
    "the complete cscroll command surface is on the system path" =
      enabled.environment.systemPackages == [ fakeCscroll ];
    "the descriptor carries Scroll's compositor mechanisms" =
      descriptor.deviceEnvironment == [ "WLR_DRM_DEVICES" ]
      && descriptor.rendererEnvironment.auto == { }
      && descriptor.rendererEnvironment.hardware == { }
      && descriptor.rendererEnvironment.software.WLR_RENDERER == "pixman"
      && descriptor.headlessEnvironment.WLR_BACKENDS == "headless"
      && descriptor.supportsHeadless
      && descriptor.supportsVirtualOutputs
      && !descriptor.supportsNotify
      && descriptor.currentDesktop == "scroll";

    "the manifest materializes the complete required Arch bundle" =
      sorted enabled.nixarch.packages.pacman
      == [
        "swaybg"
        "wlr-randr"
        "xdg-desktop-portal-wlr"
        "xorg-xwayland"
      ]
      && enabled.nixarch.packages.aur == [ ];
    "disabling nixscroll removes the complete product boundary" =
      disabled.nixarch.packages.pacman == [ ]
      && disabled.nixarch.packages.aur == [ ]
      && disabled.nixdesktop.launcher.compositors == { }
      && disabled.environment.systemPackages == [ ]
      && disabled.environment.etc == { };

    "portal routing is desktop-specific rather than global" =
      lib.attrNames enabled.environment.etc == [ portalPath ]
      && !(enabled.environment.etc ? "xdg-desktop-portal/portals.conf");
    "the portal file cannot be silently skipped" = portal.replaceExisting;
    "the portal file selects wlr capture and a general fallback" =
      lib.hasInfix "\ndefault=gtk\n" "\n${portal.text}"
      && lib.hasInfix "\norg.freedesktop.impl.portal.ScreenCast=wlr\n" portal.text
      && lib.hasInfix "\norg.freedesktop.impl.portal.Screenshot=wlr\n" portal.text;
    "the portal fallback remains configurable" =
      let text = kde.environment.etc.${portalPath}.text;
      in
      lib.hasInfix "\ndefault=kde\n" "\n${text}"
      && !(lib.hasInfix "default=gtk" text);
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
