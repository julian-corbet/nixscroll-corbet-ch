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
#
# ── THE SECOND HALF: INSTALLING A BACKEND DOES NOT SELECT IT (`nixscroll.portals`) ───────────────
#
# `install.portal.enable` above puts the wlroots backend on the box. That is necessary and NOT
# sufficient, and the gap between the two is a silent, compositor-specific failure this repo is the
# right owner of. `xdg-desktop-portal` resolves each interface by reading a `portals.conf`; with no
# matching one it falls back to the first backend it finds in lexicographical order. On a desktop
# carrying the GNOME backend as well, `gnome` sorts before `wlr`, so GNOME wins
# `org.freedesktop.impl.portal.Screenshot` and `...ScreenCast` — and its implementations are written
# against Mutter's D-Bus screencast API, which does not exist in a scroll session. Screenshot and
# screen sharing then fail with nothing in the log naming a portal, a backend, or a config file.
#
# WHY THE VENDOR FILE DOES NOT ALREADY COVER THIS. The `sway-scroll` AUR package ships
# `/usr/share/xdg-desktop-portal/scroll-portals.conf`, whose contents are exactly right. It is a
# `<desktop>-portals.conf`, so xdg-desktop-portal only ever reads it when `scroll` appears in
# `XDG_CURRENT_DESKTOP` (portals.conf(5): the desktop names come from that variable, case-folded).
# Nothing in a scroll session sets that variable — this repo's home/scroll.nix propagates it to the
# D-Bus activation environment, which passes along whatever is there and does not create it — so on
# a real host it is empty, no desktop-specific file is ever looked for, and the vendor file is inert
# on the very compositor it was written for. `nixscroll.portals.pin` therefore writes the plain,
# desktop-independent `portals.conf`, which is read whatever `XDG_CURRENT_DESKTOP` says.
#
# AND WHY NOT JUST SET `XDG_CURRENT_DESKTOP=scroll` INSTEAD. It would activate the vendor file, and
# it would also change how every `.desktop` file on the box is filtered (`OnlyShowIn=`/`NotShowIn=`
# are matched against that same variable), silently hiding or revealing application entries across
# every launcher and menu. That is a far larger and less reversible blast radius than one config
# file, for the same result, and it would leave the outcome depending on a file the AUR package
# happens to ship. Pinning is the narrow fix; the variable stays a separate question.
{ lib, config, ... }:
let
  cfg = config.nixscroll.install;
  portalsCfg = config.nixscroll.portals;

  # Mirrors the `sway-scroll` package's own `/usr/share/xdg-desktop-portal/scroll-portals.conf`
  # verbatim apart from the configurable fallback -- deliberately, so this is upstream's answer for
  # this compositor moved to a path that is actually read, rather than a policy invented here.
  #
  # `Inhibit=none` is upstream's line and is kept: the GTK backend's Inhibit implementation is
  # GNOME-session-specific and answers anything but idle-inhibit with "Inhibiting other than idle
  # not supported" (observed once per request on a live scroll session). `none` means the interface
  # has no provider, so callers fall back to the Wayland idle-inhibit protocol scroll implements
  # natively, instead of being handed a backend that errors.
  portalsConf = ''
    [preferred]
    default=${portalsCfg.pin.fallback}
    org.freedesktop.impl.portal.ScreenCast=wlr
    org.freedesktop.impl.portal.Screenshot=wlr
    org.freedesktop.impl.portal.Inhibit=none
  '';
in
{
  options.nixscroll.portals = {
    pin.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Write `/etc/xdg-desktop-portal/portals.conf`, naming the wlroots backend for
        `org.freedesktop.impl.portal.Screenshot` and `...ScreenCast`.

        THE OTHER HALF OF `install.portal.enable`, and useless without a wlroots backend present.
        Installing `xdg-desktop-portal-wlr` makes a backend available; it does not make
        `xdg-desktop-portal` route anything to it. With no `portals.conf` matching the session,
        interfaces are resolved by taking the first backend found in LEXICOGRAPHICAL order, so on
        any host that also carries `xdg-desktop-portal-gnome` the GNOME backend wins both capture
        interfaces -- and implements them against Mutter, which is not running. See the module
        header for why the vendor `scroll-portals.conf` does not already prevent this.

        WRITTEN TO /etc, NOT /usr/share, and that is the load-bearing part. portals.conf(5) ranks
        the search path with the sysconfdir copy above `$XDG_DATA_DIRS`/`/usr/share`, and within
        each location a desktop-specific `<desktop>-portals.conf` is only consulted for names
        actually present in `XDG_CURRENT_DESKTOP`. A plain `portals.conf` under /etc is therefore
        read whether or not that variable is ever set, and still outranks every vendor file if it
        later is.

        NOT A NIXOS OPTION. On NixOS the same selection is `xdg.portal.config`, and this repo's
        `nixosModules.scroll` stays thin -- see the module header's "ARCH ONLY".
      '';
    };

    pin.fallback = lib.mkOption {
      type = lib.types.str;
      default = "gtk";
      example = "kde";
      description = ''
        Backend for every interface this pin does not name explicitly, written as `default=` in the
        generated `portals.conf`.

        `gtk` matches what both `xdg-desktop-portal-gtk` and the `sway-scroll` package pick for
        themselves, and it is the right general answer on a wlroots session: the wlroots backend
        implements the two capture interfaces and nothing else, so file chooser, settings, print
        and the rest need a general backend behind it. Portals resolve per interface, not per
        session, which is what makes naming two different backends in one file correct rather than
        a conflict.

        The value is a backend basename as it appears in `/usr/share/xdg-desktop-portal/portals/`
        (`gtk` for `gtk.portal`), and the file it names must be installed -- naming a backend that
        is not there leaves those interfaces unprovided. `none` is accepted by
        xdg-desktop-portal itself and means "no provider"; `*` means "first found".
      '';
    };
  };

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
        claims only what it is right for.

        INSTALLING IS NOT SELECTING, and this option only installs. Which backend wins for which
        interface is `portals.conf`'s business, and on a host that also carries the GNOME backend
        the answer without one is `gnome` -- lexicographical order, not correctness. Pair this with
        `nixscroll.portals.pin.enable` to say it out loud; see the module header.
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

    # `replaceExisting` unconditionally, for the reason nixarch's own modules/foreign-service.nix
    # (gotcha (a)) and modules/logrotate.nix both give: system-manager DEFAULTS it to false and
    # then silently declines to write an entry whose destination already exists -- no error, no
    # warning, a module that reads as applied and did nothing. This path is unoccupied on a stock
    # Arch box (no package ships /etc/xdg-desktop-portal/), but "unoccupied today" is exactly the
    # assumption that trap punishes, and a hand-written portals.conf is a plausible thing to find
    # on a host somebody already tried to fix by hand.
    (lib.mkIf portalsCfg.pin.enable {
      environment.etc."xdg-desktop-portal/portals.conf" = {
        replaceExisting = true;
        text = portalsConf;
      };
    })
  ];
}
