# Arch/CachyOS integration for cscroll.
#
# The compositor itself is the nixscroll package, never the AUR's independent
# sway-scroll build. Registering the derivation with nixdesktop's compositor
# launcher gives systemd an absolute store path. The package's scroll-only
# wrapper supplies the Nix Mesa EGL vendor and DRI path needed on Arch; it does
# not wrap scrollmsg or the IPC helper. nixgpu/nixdesktop remain the owners of
# device selection and cgroup access, and this module adds no nixGL/runtime-PATH
# wrapper of its own.
{ self }:
{ lib, config, pkgs, ... }:
let
  cfg = config.nixscroll.install;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.scroll;
  portalsConf = ''
    [preferred]
    default=${cfg.portal.fallback}
    org.freedesktop.impl.portal.ScreenCast=wlr
    org.freedesktop.impl.portal.Screenshot=wlr
    org.freedesktop.impl.portal.Inhibit=none
  '';
in
{
  options.nixscroll.install = {
    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression
        "inputs.nixscroll.packages.\${pkgs.stdenv.hostPlatform.system}.scroll";
      description = ''
        The cscroll package registered with nixdesktop's compositor launcher.
        It provides scroll, scrollmsg and the strict-Sway IPC helper from one
        source product. The package is referenced directly by its store path;
        it is not mirrored into pacman or the AUR.
      '';
    };

    wallpaper.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install swaybg from the Arch repositories. Scroll invokes swaybg for
        image backgrounds; choosing a background remains private host policy.
      '';
    };

    outputControl.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install wlr-randr for runtime inspection and temporary changes through
        the wlroots output-management protocol.
      '';
    };

    portal.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install xdg-desktop-portal-wlr and write the Scroll-specific
        scroll-portals.conf selecting it for ScreenCast and Screenshot.
        nixdesktop's launcher sets XDG_CURRENT_DESKTOP=scroll, so a global
        portals.conf override is neither needed nor allowed here.
      '';
    };

    portal.fallback = lib.mkOption {
      type = lib.types.str;
      default = "gtk";
      example = "kde";
      description = ''
        General portal backend used for interfaces that the wlroots backend
        does not implement. The named backend must be installed separately.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Full descriptor, not just a package override. This remains sufficient
      # after nixdesktop drops its temporary built-in Scroll row.
      nixdesktop.launcher.compositors.scroll = {
        package = cfg.package;
        command = "scroll";
        env = [ "WLR_DRM_DEVICES" ];
        supportsVirtualOutputs = true;
        supportsNotify = false;
        currentDesktop = "scroll";
      };
    }

    # These companion packages are compositor-specific but independent. The
    # Arch reconciler owns their installation; cscroll itself never enters an
    # AUR or pacman list.
    (lib.mkIf cfg.wallpaper.enable {
      nixarch.packages.pacman = [ "swaybg" ];
    })
    (lib.mkIf cfg.outputControl.enable {
      nixarch.packages.pacman = [ "wlr-randr" ];
    })
    (lib.mkIf cfg.portal.enable {
      nixarch.packages.pacman = [ "xdg-desktop-portal-wlr" ];
      environment.etc."xdg-desktop-portal/scroll-portals.conf" = {
        # system-manager otherwise skips an occupied destination silently.
        replaceExisting = true;
        text = portalsConf;
      };
    })
  ];
}
