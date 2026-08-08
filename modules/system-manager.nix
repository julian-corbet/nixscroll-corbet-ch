# Arch/CachyOS plane — declare scroll's package name, and the wlroots companions its session needs,
# into nixarch's reconciler.
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
#
# ── THE COMPANIONS, AND WHY THEY BELONG TO THIS REPO RATHER THAN A DESKTOP LAYER ────────────────
#
# Three protocol-specific tools below (`wallpaper`, `outputControl`, `portal`). Each one talks to a
# wlroots protocol extension that scroll implements BY BEING A SWAY FORK, and each one is inert or
# absent on a compositor that is not one — a GNOME or KDE session has its own wallpaper mechanism,
# its own output-management protocol and its own portal backend, and would gain nothing from these.
# So they are not "desktop furniture a host might also want": they are the parts of a working
# session that are true of THIS compositor family and no other, which is exactly the subject this
# repo owns.
#
# INDEPENDENT OPTIONS, NOT ONE `companions.enable`. A host that runs scroll under a display manager
# on a machine with one fixed output has no use for a runtime output tool, and a host that never
# screen-shares does not need a portal backend running. Lumping them would mean enabling any of the
# three installs all of them; each is therefore its own boolean, and none is on by default.
#
# NOT GATED ON `enable`, DELIBERATELY. `enable` above answers "does this box install scroll from the
# AUR" — and a host may legitimately answer no while still running scroll: `nixdesktop`'s own role
# table already resolves `compositor = "scroll"` to the same `sway-scroll` name, so a box wired that
# way gets the compositor from there and would still want the companions from here. Making them
# depend on `enable` would silently install nothing on precisely that host.
#
# ARCH ONLY, and this repo's NixOS module stays out of it. `nixosModules.scroll` is thin on purpose
# (see its own header and the README's "The split"): package plus wayland-sessions entry, no portal
# config, no extra packages. That is not an oversight to correct here — a portal backend on NixOS is
# `xdg.portal.extraPortals`, not a package in a list, and dropping
# `pkgs.xdg-desktop-portal-wlr` into `environment.systemPackages` produces an installed binary that
# is registered in no `portals.conf` and therefore invisible to every portal request. Same asymmetry
# nixdesktop's own role table already documents for its `portals` capability. On Arch the package IS
# the mechanism: pacman drops the `.portal` file and the D-Bus service into the one shared prefix
# `xdg-desktop-portal` already reads.
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

    wallpaper.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install `swaybg`, the wallpaper tool for wlroots compositors (official Arch `extra`).

        WHAT THIS DOES AND DOES NOT DECIDE. It installs a binary and nothing else. It does not
        choose a wallpaper, does not render a `swaybg` invocation into any startup unit, and does
        not write scroll's own `output <name> background ...` directive -- `programs.scroll`'s
        per-output `background` option (home/scroll.nix) is the place that directive is generated
        from, and it stays exactly as it was: `null` by default, raw when set. Which of the two
        mechanisms a host uses to actually put an image on screen is deliberately still an open
        question here, and this option is compatible with either answer, because both of them need
        this binary present: scroll inherits sway's `swaybg_command`, so even the compositor's own
        `output ... background` directive shells out to `swaybg` and silently does nothing without
        it.

        Off by default. A host that sets a solid colour through scroll's own `background`
        (`<colour> solid_color`) needs no external process at all, and a headless or
        single-purpose session needs no wallpaper mechanism whatsoever.
      '';
    };

    outputControl.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install `wlr-randr`, the runtime output tool for wlroots compositors (official Arch
        `extra`).

        WHY IT IS NOT REDUNDANT WITH THE DECLARED LAYOUT. `programs.scroll` renders each output's
        mode, position, scale and transform into the config scroll reads at startup -- that is the
        host's stated intent, and it is the right owner of it. This is the other half: reading back
        what the compositor ACTUALLY did (`wlr-randr` with no arguments enumerates every live
        output, its current mode and the modes it advertises), and changing one for the length of a
        session without editing a declaration. Those are the two things a rendered config cannot
        do, and both are how a wrong layout gets diagnosed in the first place.

        SPEAKS `wlr-output-management-v1`, which is why this is a wlroots-family tool rather than a
        general one: `xrandr` needs an X server, and the desktop environments' own display panels
        speak their own protocols. On a compositor that does not implement that extension this
        binary reports nothing at all.
      '';
    };

    portal.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install `xdg-desktop-portal-wlr`, the xdg-desktop-portal BACKEND for wlroots compositors
        (official Arch `extra`).

        THE BACKEND IS WHAT SCREEN CAPTURE ACTUALLY IS ON THIS COMPOSITOR. `xdg-desktop-portal`
        itself implements no capture; it routes a request to whichever backend claims the interface
        for the running session. `org.freedesktop.impl.portal.ScreenCast` and `...Screenshot` are
        exactly the two this backend provides, and it provides them by speaking
        `wlr-screencopy`/`wlr-export-dmabuf` -- protocols a wlroots compositor implements and no
        other family does. A session running scroll with only the GTK and GNOME backends installed
        therefore has no correct provider for those two interfaces: the GNOME backend's screencast
        implementation is written against Mutter's own D-Bus screencast API, which is not present
        here, so screen sharing is either broken outright or being served by a backend that does
        not match the compositor.

        NOT A REPLACEMENT FOR THE GENERAL BACKENDS, and this option does not touch them. A desktop
        still wants the GTK backend for file chooser, settings, and the rest -- portals are
        resolved per interface, not per session, so the wlroots backend sits alongside them and
        claims only what it is right for. Which backend wins for which interface is
        `portals.conf`'s business (`/usr/share/xdg-desktop-portal/`, plus whatever a compositor
        ships -- scroll's package installs its own `scroll-portals.conf`), not this module's.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      nixarch.packages.aur = [ cfg.aurPackage ];
    })

    # The three companions are official-repo names on upstream Arch, so they go to the pacman half
    # rather than the AUR one -- verified against `pacman -Si` on two live CachyOS hosts (each
    # served as a `cachyos-extra-v3` rebuild, which is a rebuild of the Arch repo rather than a
    # derivative-only package) and against archlinux.org's package search, with the AUR RPC
    # returning nothing for any of the three. One `mkIf` each rather than a computed list: these
    # are independent decisions, and a list would only re-introduce the ordering question that a
    # merge of three singleton lists does not have.
    (lib.mkIf cfg.wallpaper.enable { nixarch.packages.pacman = [ "swaybg" ]; })
    (lib.mkIf cfg.outputControl.enable { nixarch.packages.pacman = [ "wlr-randr" ]; })
    (lib.mkIf cfg.portal.enable { nixarch.packages.pacman = [ "xdg-desktop-portal-wlr" ]; })
  ];
}
