# Arch/CachyOS plane — declare scroll's package name into nixarch's reconciler.
#
# This module says WHAT to install; nixarch's own `nixarch.packages` mechanism installs it. Import
# alongside `nixarch.systemManagerModules.packages`, or the list is computed and nothing acts on it.
# Same contract nixgpu.toolchain uses for its ROCm/CUDA names.
#
# WHY a separate plane at all: scroll is NOT in nixpkgs, so unlike niri it cannot be resolved by
# nixdesktop's role table (`lib/nixos-roles.nix` maps a role name to a `pkgs.*` attribute). On NixOS
# that gap is filled by this repo's `nixosModules.scroll`, which installs the flake's own package
# passthrough. On Arch the equivalent is the AUR package, named in scroll's own README:
#
#   Stable version: `sway-scroll`. Currently at 1.12. ... You should be able to have any version of
#   `sway` and `scroll` installed on the same system and start any of them without problems.
#
# It goes to `nixarch.packages.aur`, not `.pacman` — it is not in the Arch repos, and routing an
# AUR-only name to the repo list is exactly the failure nixarch's desktop-backend splits to avoid.
#
# NOTE for Artix / non-systemd Arch derivatives: scroll's README documents that the AUR package
# does not work out of the box there, because it links elogind rather than systemd's login daemon.
# That is an upstream packaging matter, not something this module can paper over.
{ lib, config, ... }:
let
  cfg = config.nixscroll.install;
in
{
  options.nixscroll.install = {
    enable = lib.mkEnableOption "installing scroll on an Arch/CachyOS host via nixarch's package reconciler";

    aurPackage = lib.mkOption {
      type = lib.types.str;
      default = "sway-scroll";
      example = "sway-scroll-git";
      description = ''
        AUR package providing scroll. `sway-scroll` tracks the stable release;
        `sway-scroll-git` tracks upstream. Both install binaries named `scroll`,
        `scrollmsg`, `scrollbar` and `scrollnag`, so they coexist with a real
        `sway` install rather than conflicting with it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nixarch.packages.aur = [ cfg.aurPackage ];
  };
}
