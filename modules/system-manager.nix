# Arch/CachyOS integration for cscroll.
#
# The compositor itself is the nixscroll package, never the AUR's independent
# sway-scroll build. Registering the derivation with nixdesktop's compositor
# launcher gives systemd an absolute store path. The package's scroll-only
# wrapper supplies the Nix Mesa EGL vendor and DRI path needed on Arch; it does
# not wrap scrollmsg or the IPC helper. nixgpu/nixdesktop remain the owners of
# device selection and cgroup access, and this module adds no nixGL/runtime-PATH
# wrapper of its own.
{ self, runtimeManifest, descriptorFor }:
{ lib, config, pkgs, ... }:
let
  cfg = config.nixscroll;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.scroll;
  requiredExternal = lib.filter
    (component:
      component.required
      && component.kind != "bundled-command")
    runtimeManifest.component;
  componentById = id:
    let
      matches = lib.filter (component: component.id == id) runtimeManifest.component;
    in
    if builtins.length matches == 1
    then builtins.head matches
    else throw "nixscroll: runtime manifest must contain exactly one component named ${id}";
  portalComponent = componentById "capture-portal";
  archPackages = map
    (component:
      component.arch-package
      or (throw "nixscroll: component ${component.id} has no Arch package mapping"))
    requiredExternal;
  portalsConf = ''
    [preferred]
    default=${cfg.portalFallback}
    org.freedesktop.impl.portal.ScreenCast=wlr
    org.freedesktop.impl.portal.Screenshot=wlr
    org.freedesktop.impl.portal.Inhibit=none
  '';
in
{
  options.nixscroll = {
    enable = lib.mkEnableOption ''
      the complete cscroll runtime product, including every required external
      component declared by cscroll's runtime-components.toml
    '';

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

    portalFallback = lib.mkOption {
      type = lib.types.str;
      default = "gtk";
      example = "kde";
      description = ''
        General portal backend used for interfaces that the wlroots backend
        does not implement. The named backend must be installed separately.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.all
            (component:
              component.required
              && component ? command
              && component ? reason)
            runtimeManifest.component;
        message =
          "nixscroll: every cscroll runtime component must be required and "
          + "carry a command and reason";
      }
      {
        assertion =
          portalComponent.configuration
          == "resources/scroll-portals.conf";
        message =
          "nixscroll: cscroll's capture portal must retain the "
          + "resources/scroll-portals.conf contract";
      }
    ];

    nixdesktop.launcher.compositors.scroll = descriptorFor cfg.package;

    # The runtime manifest, not a second hand-maintained list, decides the
    # complete set removed when nixscroll is disabled.
    nixarch.packages.pacman = archPackages;

    environment.etc."xdg-desktop-portal/scroll-portals.conf" = {
      # system-manager otherwise skips an occupied destination silently.
      replaceExisting = true;
      text = portalsConf;
    };
  };
}
