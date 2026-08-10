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

    # The second option this module writes to, stubbed to the same minimum as the package lists
    # above: only the two attributes the portals pin actually sets. system-manager's real
    # environment.etc carries `target`, `mode`, `user`, `group` and a `source`/`text` derivation
    # bridge, none of which this module touches and none of which needs reproducing to observe
    # what it renders.
    options.environment.etc = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          text = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          replaceExisting = lib.mkOption { type = lib.types.bool; default = false; };
        };
      });
    };
  };

  evaluateAll = extraConfig:
    (lib.evalModules { modules = [ systemManagerModule stubs extraConfig ]; }).config;

  evaluate = extraConfig: (evaluateAll extraConfig).nixarch.packages;

  etcOf = extraConfig: (evaluateAll extraConfig).environment.etc;

  portalsPath = "xdg-desktop-portal/portals.conf";
  pinned = etcOf {
    nixscroll.install.portal.enable = true;
    nixscroll.portals.pin.enable = true;
  };
  pinnedConf = pinned.${portalsPath} or null;

  nothing = evaluate { };
  compositorOnly = evaluate { nixscroll.install.enable = true; };
  companionsOnly = evaluate {
    nixscroll.install = {
      wallpaper.enable = true;
      wallpaperPicker.enable = true;
      outputControl.enable = true;
      portal.enable = true;
    };
  };
  everything = evaluate {
    nixscroll.install = {
      enable = true;
      aurPackage = "sway-scroll-git";
      wallpaper.enable = true;
      wallpaperPicker.enable = true;
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

    # All four companions are official-repo names; the reverse leak (a repo name sent to an AUR
    # helper) is not fatal but is a needless source build, so it is checked in both directions too.
    "the companions go to the pacman list and never to the AUR one" =
      sorted companionsOnly.pacman == [ "azote" "swaybg" "wlr-randr" "xdg-desktop-portal-wlr" ]
      && companionsOnly.aur == [ ];

    # The load-bearing independence claim from the module's own header: the companions are NOT
    # gated on `enable`, because nixdesktop's role table can already supply the compositor itself.
    # A regression that added that gate would silently install nothing on exactly that host.
    "the companions do not depend on the compositor's own install being enabled" =
      companionsOnly.pacman != [ ];

    # ...and each companion is independent of the other three, so enabling one cannot drag in four.
    "each companion is its own decision" =
      (evaluate { nixscroll.install.portal.enable = true; }).pacman == [ "xdg-desktop-portal-wlr" ];

    # Asserted specifically for the pair that a reader is most likely to assume implies the other:
    # azote is a front end for swaybg, but the picker does NOT pull in the tool, because a host that
    # wants the wallpaper mechanism without a GUI browser for it is the ordinary case.
    "the wallpaper picker does not imply the wallpaper tool" =
      (evaluate { nixscroll.install.wallpaperPicker.enable = true; }).pacman == [ "azote" ];

    "the wallpaper tool does not imply the picker" =
      (evaluate { nixscroll.install.wallpaper.enable = true; }).pacman == [ "swaybg" ];

    "both halves compose without either erasing the other" =
      sorted everything.pacman == [ "azote" "swaybg" "wlr-randr" "xdg-desktop-portal-wlr" ]
      && everything.aur == [ "sway-scroll-git" ];

    # ── The portals pin ────────────────────────────────────────────────────────────────────────
    #
    # Same default-off stance as the packages: composing this plane must not start writing files
    # into a consumer's /etc.
    "an unconfigured host gets no portals.conf" =
      etcOf { } == { };

    # Installing the backend and selecting it are separate decisions in both directions -- the
    # module header's whole point is that the first without the second is the silent failure.
    "installing the wlroots backend does not by itself write a portals.conf" =
      etcOf { nixscroll.install.portal.enable = true; } == { };

    # THE PATH IS THE FIX. A `<desktop>-portals.conf` is only read when that name appears in
    # XDG_CURRENT_DESKTOP, which nothing in a scroll session sets -- which is exactly why the
    # vendor `scroll-portals.conf` is inert and this file is not. A regression that renamed this
    # to `scroll-portals.conf`, or moved it under /usr/share, would restore the original bug while
    # still looking like a portal config, so the destination is asserted literally.
    "the pin lands at the desktop-independent /etc path" =
      lib.attrNames pinned == [ portalsPath ];

    # See modules/system-manager.nix's own note: system-manager defaults this to false and then
    # SILENTLY skips an occupied destination, so losing it turns the fix into a no-op with no
    # error anywhere.
    "the pin replaces an existing file rather than silently skipping it" =
      pinnedConf != null && pinnedConf.replaceExisting;

    # The two interfaces this repo exists to get right. Asserted as whole lines, because the key
    # is the fully-qualified interface name and a truncated one silently matches nothing.
    "the pin names the wlroots backend for both capture interfaces" =
      pinnedConf != null
      && lib.hasInfix "\norg.freedesktop.impl.portal.ScreenCast=wlr\n" pinnedConf.text
      && lib.hasInfix "\norg.freedesktop.impl.portal.Screenshot=wlr\n" pinnedConf.text;

    # ...and the general backend still gets everything else, which is what makes naming two
    # backends in one file correct rather than a conflict.
    "the pin leaves every other interface to the fallback backend" =
      pinnedConf != null
      && lib.hasInfix "\n[preferred]\ndefault=gtk\n" "\n${pinnedConf.text}";

    "the fallback backend is honoured rather than hardcoded" =
      let
        # `or null`, like `pinnedConf` above, so that a regression which MOVES this file fails as
        # the named assertion below rather than as a bare "attribute missing" trace out of this
        # let-binding -- which is what it did before the guard, burying the real message.
        kde = (etcOf {
          nixscroll.portals.pin = { enable = true; fallback = "kde"; };
        }).${portalsPath} or null;
      in
      kde != null
      && lib.hasInfix "\ndefault=kde\n" "\n${kde.text}"
      && !(lib.hasInfix "default=gtk" kde.text)
      # ...and changing it must not disturb the two lines that are the point of the file.
      && lib.hasInfix "\norg.freedesktop.impl.portal.Screenshot=wlr\n" kde.text;
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
