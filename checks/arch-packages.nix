# Evaluates modules/system-manager.nix for real, and asserts the AUR/pacman split it publishes.
#
# WHY THIS FILE EXISTS AT ALL, the same blind spot checks/startup-contract.nix opens with:
# `nix flake check` does not evaluate `systemManagerModules`. It reports them as "unchecked" and
# moves on -- so until now the entire Arch plane was untested, and it is the plane that decides
# which of two package LISTS a name lands in. That distinction is not cosmetic on this platform:
# `pacman -S` fails the WHOLE transaction on one unresolvable target, so an AUR-only name leaking
# into the repo list takes every other package on the host down with it, while a repo name sent to
# an AUR helper merely builds from source needlessly. The two lists are the module's whole output
# and neither is observable without evaluating it.
#
# The stub below is a deliberately minimal stand-in for the ONE option this module writes to
# (`nixarch.packages.{pacman,aur}`), not an attempt to vendor nixarch: the point is to exercise
# THIS module's logic. Both are plain `listOf str` at the default priority in nixarch's own
# modules/packages.nix, which is exactly what makes a consumer's list concatenate with this
# module's rather than fight it -- so the stub reproduces that shape and nothing else.
{ pkgs, lib ? pkgs.lib, systemManagerModule }:
let
  stubs = { lib, ... }: {
    options.nixarch.packages = {
      pacman = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
      aur = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  evaluate = extraConfig:
    (lib.evalModules { modules = [ systemManagerModule stubs extraConfig ]; }).config.nixarch.packages;

  nothing = evaluate { };
  compositorOnly = evaluate { nixscroll.install.enable = true; };
  companionsOnly = evaluate {
    nixscroll.install = {
      wallpaper.enable = true;
      outputControl.enable = true;
      portal.enable = true;
    };
  };
  everything = evaluate {
    nixscroll.install = {
      enable = true;
      aurPackage = "sway-scroll-git";
      wallpaper.enable = true;
      outputControl.enable = true;
      portal.enable = true;
    };
  };

  sorted = lib.sort (a: b: a < b);

  results = {
    # A module composed and asked for nothing must declare nothing. The default-off stance is what
    # lets a consumer import this plane unconditionally alongside the rest of the flake.
    "an unconfigured host gets no packages at all" =
      nothing.pacman == [ ] && nothing.aur == [ ];

    # THE FATAL DIRECTION, asserted rather than assumed: scroll's own package is AUR-only and must
    # never appear in the pacman list.
    "scroll goes to the AUR list and never to the pacman one" =
      compositorOnly.aur == [ "sway-scroll" ] && compositorOnly.pacman == [ ];

    "aurPackage is honoured rather than hardcoded" =
      lib.elem "sway-scroll-git" everything.aur && !(lib.elem "sway-scroll" everything.aur);

    # The three companions are official-repo names; the reverse leak (a repo name sent to an AUR
    # helper) is not fatal but is a needless source build, so it is checked in both directions too.
    "the companions go to the pacman list and never to the AUR one" =
      sorted companionsOnly.pacman == [ "swaybg" "wlr-randr" "xdg-desktop-portal-wlr" ]
      && companionsOnly.aur == [ ];

    # The load-bearing independence claim from the module's own header: the companions are NOT
    # gated on `enable`, because nixdesktop's role table can already supply the compositor itself.
    # A regression that added that gate would silently install nothing on exactly that host.
    "the companions do not depend on the compositor's own install being enabled" =
      companionsOnly.pacman != [ ];

    # ...and each companion is independent of the other two, so enabling one cannot drag in three.
    "each companion is its own decision" =
      (evaluate { nixscroll.install.portal.enable = true; }).pacman == [ "xdg-desktop-portal-wlr" ];

    "both halves compose without either erasing the other" =
      sorted everything.pacman == [ "swaybg" "wlr-randr" "xdg-desktop-portal-wlr" ]
      && everything.aur == [ "sway-scroll-git" ];
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
# `pkgs.emptyFile` rather than a `runCommand` marker -- see checks/startup-contract.nix's own
# closing comment for why (`--all-systems` would turn a system-dependent output path into a real
# cross-platform build and fail on the runner).
if failed == [ ]
then pkgs.emptyFile
else throw ''
  nixscroll: the Arch package plane is wrong. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
