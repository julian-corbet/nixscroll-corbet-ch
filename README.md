# nixscroll

Declarative config generation for [cscroll](https://github.com/corbet-labs/cscroll), a deliberately
close downstream of [scroll](https://github.com/dawsers/scroll) — a fork of
[sway](https://github.com/swaywm/sway) with a scrolling, PaperWM-style tiling layout — plus the
packaging and system wiring it needs since Scroll is not in nixpkgs. Four outputs:
a package built from cscroll, a home-manager module that writes `~/.config/scroll/config` from
structured options, a thin NixOS module for the system side, and an Arch/CachyOS plane that
registers cscroll with the compositor launcher and names optional companions for the distro
reconciler.

## The split

Four pieces, because scroll not being in nixpkgs is a real constraint that shapes the whole repo:

**Packaging** (`packages.<system>.scroll`) — builds the non-flake `cscroll` source input through
[Diax170/scroll-flake](https://github.com/Diax170/scroll-flake)'s maintained Sway/wlroots recipe.
Both of scroll-flake's own source inputs follow `cscroll`, so the recipe cannot silently reach
around the runtime-product boundary to upstream Scroll. Full credit to
[Diax170](https://github.com/Diax170) for the packaging work; nixscroll selects the source and adds
two narrow runtime provisions. Only the `scroll` executable exports Nix Mesa's EGL-vendor file and
`LIBGL_DRIVERS_PATH`, which is required when this Nix-built compositor runs on Arch; no
hardware-specific Vulkan ICD is guessed. The IPC helper's `/usr/bin/env python3` shebang is patched
to an absolute Nix-store interpreter during fixup. Neither provision adds Python or Mesa tools to
the compositor's runtime `PATH`, and neither wraps `scrollmsg` or the IPC helper.

Until `corbet-labs/cscroll` exists publicly, evaluate a local checkout with an ephemeral override:

```sh
nix flake check --override-input cscroll path:/path/to/cscroll --no-write-lock-file
```

No machine-local path belongs in `flake.nix` or `flake.lock`. The real cscroll lock entry is made
after publication.

**Config generation** (`homeManagerModules.scroll`, namespace `programs.scroll`) — a home-manager
module that renders `~/.config/scroll/config` from a structured option tree instead of hand-edited
sway-syntax text. Installs nothing: it assumes a `scroll` binary exists somewhere on `$PATH` (or
gets installed by the NixOS module below, or by hand, or by a distro package) and writes config
for it. This is the module most consumers want.

**System install** (`nixosModules.scroll`, same `programs.scroll` namespace) — installs the
package and registers scroll as a selectable wayland-sessions entry for a display manager. Kept
deliberately thin — no module-level wrapper customization, no XDG portal config, no extra
packages. (The package itself still carries the fixed Mesa environment described above.) If you
want that fuller sway.nix-style module, scroll-flake ships its own `nixosModules.default` under
this same namespace; use one or the other, not both, since they'd both try to own
`programs.scroll`.

**Arch/CachyOS** (`systemManagerModules.scroll`, namespace `nixscroll.install`) — registers the
full Scroll descriptor in `nixdesktop.launcher.compositors.scroll`, including this flake's cscroll
derivation. The seated unit therefore executes the Nix-store compositor directly; it never falls
back to the independent AUR `sway-scroll` build. The package's `scroll`-only wrapper keeps the Nix
Mesa EGL/DRI closure usable on Arch, while nixgpu/nixdesktop retain device selection and cgroup
ownership; no nixGL wrapper or Python runtime entry is added to the compositor's `PATH`.

Three optional companions remain Arch package names: `swaybg`, `wlr-randr`, and
`xdg-desktop-portal-wlr`. Each is independent and off by default. Enabling the portal backend also
writes `/etc/xdg-desktop-portal/scroll-portals.conf`, selecting `wlr` for ScreenCast and Screenshot
and a configurable general fallback (`portal.fallback`, default `gtk`). This file is
desktop-specific because nixdesktop's launcher now sets `XDG_CURRENT_DESKTOP=scroll`; nixscroll no
longer writes a global `/etc/xdg-desktop-portal/portals.conf` override.

Neither the config-generation module nor the NixOS module invents its own option namespace per
project convention — both use `programs.scroll`, matching how nixpkgs itself names
`programs.sway` and how scroll-flake already named its own NixOS module, so the same mental model
(and, for the NixOS side, literally the same option path) carries over.

## Modules

| Output | Class | Owns |
|---|---|---|
| `packages.<system>.scroll` | flake package | cscroll source built with `Diax170/scroll-flake`'s recipe; includes `scroll`, `scrollmsg`, and `scroll-swayipc-compat` |
| `homeManagerModules.scroll` (`.default`) | home-manager | `~/.config/scroll/config`, generated from `programs.scroll.*`. Installs nothing. |
| `homeManagerModules.ipcCompat` | home-manager | selects cscroll's packaged strict-Sway IPC helper (`programs.scroll.ipcCompat`) and optionally declares its user unit — see [Strict sway clients](#strict-sway-clients) below. Contains no proxy implementation. |
| `nixosModules.scroll` (`.default`) | NixOS | `environment.systemPackages` + `services.displayManager.sessionPackages` for `programs.scroll.package` |
| `systemManagerModules.scroll` (`.default`) | [system-manager](https://github.com/numtide/system-manager) (Arch/CachyOS) | full `nixdesktop` compositor descriptor pointing at cscroll; optional Arch companions; desktop-specific `/etc/xdg-desktop-portal/scroll-portals.conf` when the portal backend is enabled |

## Not scroll's own named keymap modes

scroll's shipped default config defines a set of i3/sway modal keybinding blocks —
`mode "wssplit" { ... }`, `mode "jump" { ... }`, `mode "filter" { ... }`, and likewise for
`modifiers`, `setsizeh`, `setsizev`, `resize`, `floating`, `togglesizeh`, `togglesizev`, `align`,
`fit_size`, `trailmark`, `trail`, and `spaces`. These are **not** scroll mechanisms — they're
ordinary sway modal keymaps scroll inherited by being a sway fork, and scroll's own package
already ships working defaults for every one of them (see its `/etc/scroll/config`). There is
deliberately no option per mode name here; that would be modeling sway's generic keymap feature,
not scroll. Real scroll-specific directives (`layout_*`, `animations`, `jump_labels_*`,
`gesture_scroll_*`, `snap_*`, ...) get real options below. Keymaps of any kind — including
overriding scroll's own named modes with different keys — go through the generic
`programs.scroll.binds`/`programs.scroll.modes` escape hatch.

## Strict sway clients

scroll speaks sway's IPC protocol, so every sway client finds it. What it does not do is speak
sway's exact **schema**, and a client that deserializes strictly — Rust clients built on `swayipc`
are the common case — dies on the difference:

```
scroll:  layout = horizontal | vertical | none | output
sway:    layout = splith | splitv | stacked | tabbed | output | dockarea | none
```

`unknown variant 'vertical', expected one of ...`, and that part of the client is gone. Neither side
is misbehaving: the compositor reports its own layout model honestly, and the client validates
against the schema it was written for. Scroll is the diverging runtime, so the repair belongs in
cscroll rather than in a client or this Nix integration.

The runtime repair lives in cscroll's installed `scroll-swayipc-compat` executable. It translates
only the lossless schema pairs `horizontal` → `splith` and `vertical` → `splitv`, in the
compositor-to-client direction, and recomputes frame lengths. `homeManagerModules.ipcCompat`
contains no generated proxy program: it selects the cscroll package by absolute store path and
optionally declares the user unit around it.

```nix
imports = [ inputs.nixscroll.homeManagerModules.ipcCompat ];

programs.scroll.ipcCompat = {
  enable = true;
};
```

Then point the client at it. **Both halves are required**:

```nix
systemd.user.services.my-bar.Service = {
  Environment = [ "SWAYSOCK=${config.programs.scroll.ipcCompat.socketPath}" ];
  UnsetEnvironment = config.programs.scroll.ipcCompat.unsetVariables;
};
```

Setting `SWAYSOCK` **alone is inert**. scroll exports `SCROLLSOCK` into the systemd user
environment, and a sway client library probes the socket variables in its own priority order, so it
finds that one first and connects straight past the proxy. Nothing errors — the client simply
behaves as though the proxy were not installed, which is indistinguishable from the proxy being
broken.

Workspace IDs, missing-workspace synthesis, pinned buttons and `change: "empty"` events are not
rewritten. Those are client/UI policy and belong in a native client adapter such as cbar's, not in
a compositor protocol bridge.

Reported upstream as [ironbar#1584](https://github.com/JakeStanger/ironbar/issues/1584).

## Software rendering

`programs.scroll.softwareRendering.enable` exists for machines with no real GPU — the primary
target for this module is an ASPEED AST2500 server BMC running scroll under pixman's software
rasterizer. When true, it switches `animations`, `decoration.shadow`, and `decoration.dim` off
and `decoration.borderRadius` to `0` — the parts of scroll's rendering that are genuinely
GPU-bound work. Under a hardware compositor these are close to free; under pixman they cost real
CPU time every frame, on a box that has none to spare. Every one of those defaults is applied via
`mkDefault`, never forced — set any of them explicitly yourself and your value wins regardless of
this flag.

## Usage

```nix
{
  imports = [ inputs.nixscroll.homeManagerModules.scroll ];

  programs.scroll = {
    enable = true;
    settings = {
      modifier = "Mod4";
      terminal = "kitty";
      gaps.inner = 4;
      gaps.outer = 12;
    };
    layout.widths = [ 0.33333333 0.5 0.66666667 1.0 ];
    softwareRendering.enable = true; # no GPU on this box
    outputs."DP-1" = {
      resolution = "2560x1440@144Hz";
      position = "0 0";
    };
    binds."Mod4+Return" = "exec kitty";
    extraConfig = ''
      # anything not covered by an option above, appended verbatim, last
    '';
  };
}
```

Add the system side only if you also want scroll installed and listed by your display manager:

```nix
{
  imports = [ inputs.nixscroll.nixosModules.scroll ];
  programs.scroll.enable = true;
}
```

## Mechanism public, values private

Every default in this repo is either scroll's own upstream default (rendered only when you
actually set the option — see "render only what you set" below) or a neutral placeholder. No
default here bakes in a specific machine's output name, monitor resolution, keyboard layout, or
key layout — `outputs` is `{}` by default (scroll auto-detects), `binds`/`modes` are `{}` (scroll
ships its own working defaults already). A consumer's own hostnames and hardware go in their own
config, never in this repo's defaults.

## Render only what you set

The generated config never emits a directive for an option you didn't touch — every scalar option
defaults to `null` (skip it) rather than to scroll's actual documented default, and the module
comments each one with what scroll itself defaults to when left unset. This keeps the generated
file short and diffable, and means scroll's own upstream defaults keep working even for options
this module doesn't happen to expose yet.

## Status

Pre-alpha scaffold. Verified so far: the home-manager module's option tree evaluates cleanly
(`lib.evalModules` against a stand-in home-manager scaffold) and renders the expected config text
for a representative set of options, including the `softwareRendering.enable` → `mkDefault`
chain (confirmed overridable) and the `binds`/`modes` null-unbind semantics; the NixOS module
evaluates cleanly against a stand-in NixOS scaffold and resolves `programs.scroll.package` to the
expected derivation. **Not yet verified**: a real `home-manager switch` producing a config scroll
itself accepts without complaint, or an actual scroll session running under either module. Treat
the option surface as exactly what it is — a first pass derived from scroll's own man pages
(`scroll.5`, `scroll-input.5`, `scroll-output.5`, `scroll-bar.5`), not yet run against the real
binary.

## Related projects

nixscroll is one of several small, independently-usable open-source projects sharing a common
design system: [nixdesktop](https://github.com/julian-corbet/nixdesktop-corbet-ch) (a
a compositor-neutral CPU-rendered desktop policy layer) and [nixremote](https://github.com/julian-corbet/nixremote-corbet-ch)
(declarative cross-machine Wayland app forwarding) cover adjacent ground on the same
Wayland-on-Nix theme; nixscroll's own niche is scroll specifically, for anyone who wants its
scrolling layout instead of a grid-based compositor.

## License

[MIT License](LICENSE) © 2026 Julian Corbet

## Idle and lock: not here, by design

`programs.scroll` has no idle-timeout or screen-locker options, and should not grow any.
[nixdesktop][nixdesktop] owns them — `nixdesktop.session.idleAndLock` takes `lockAfterSeconds`,
`suspendAfterSeconds` and `lockCommand`, assembles the `swayidle` invocation, and runs it as a
systemd user service.

That is not an omission waiting to be filled. `swayidle`'s invocation is byte-identical under any
wlroots compositor, and "lock after 30 minutes, never suspend" describes the *host*, not scroll's
config syntax. Adding the options here would create a second copy of the same policy — one per
compositor repo, free to drift. nixniri used to carry exactly that copy and has given it up.

What is legitimately scroll's is the lock **keybind**. Since this repo ships no default bind table
(`binds` starts empty and scroll's own upstream defaults apply), bind it yourself, reading the
locker from the single place it is declared:

```nix
programs.scroll.binds."$mod+Alt+l" =
  "exec ${config.nixdesktop.session.idleAndLock.lockCommand}";
```

[nixdesktop]: https://github.com/julian-corbet/nixdesktop-corbet-ch

## Wiring nixdesktop's shared startup list

[nixdesktop](https://github.com/julian-corbet/nixdesktop-corbet-ch) is the compositor-neutral
policy layer. Its shared components — a notification daemon, a widget shell — append the commands
they need to a neutral `nixdesktop.startup` list rather than writing into any compositor's
namespace.

**This module splices that list for you.** Nothing to wire: `home/scroll.nix` reads
`config.nixdesktop.startup` through `lib.probeFact` (consumed from
[nixhost](https://github.com/julian-corbet/nixhost-corbet-ch)'s own `lib/facts.nix` via this
repo's own `nixhost` flake input) and emits each entry
as its own `exec` line, ordered ahead of anything you put in `programs.scroll.startup` — contract
entries are session components a host's own commands may expect to be running already.

If no nixdesktop module is in scope at all, the read yields an empty list and nothing extra is
rendered. No flake input on nixdesktop is involved, and none is needed; this is the same
defensive-read idiom nixboot uses for `nixstorage.layout` and nixhost uses for the facts it
mirrors. The dependency stays one-way: nixdesktop declares the contract and knows nothing about
scroll.

> **This used to be your job, and it was a trap.** Earlier versions asked you to write
> `programs.scroll.startup = config.nixdesktop.startup;` yourself, on the stated grounds that a
> compositor module *cannot* read an option from a repo it does not depend on. That premise was
> simply wrong — a defensive read needs no dependency. The cost of believing it was a silent
> failure mode: forget the line and the component is fully configured, its files written, and it
> never launches, with no error possible, because a populated list with no reader is a valid
> configuration. `checks/startup-contract.nix` now asserts the splice in both directions, since
> `nix flake check` does not evaluate `homeManagerModules` and so never covered this at all.
>
> **A second, quieter version of the same trap survives even after the splice is automatic:**
> `nixdesktop.startup` has a genuine `[ ]` default, so if nixdesktop ever renamed it, the read
> would resolve to the SAME empty list a never-imported nixdesktop produces — silently, with no
> error, exactly like the original incident, just one layer further back (the list itself
> unreachable, not merely unread). A bare `config.nixdesktop.startup or [ ]` cannot tell the two
> apart; `lib.probeFact` can, and warns only for the rename. `checks/startup-contract.nix`'s own
> fact-wiring group proves it fires.

`programs.scroll.startup` remains yours for the host's own commands, and still takes bare commands
rather than raw config lines. (niri's native startup syntax takes raw KDL, so nixniri translates the
same neutral list into `spawn-sh-at-startup` lines instead — each compositor module adapts the
contract to its own syntax, which is the point of the contract being neutral.)

## Wiring nixdisplay's monitors, layouts and nixdesktop's device permission

[nixdisplay](https://github.com/julian-corbet/nixdisplay-corbet-ch) owns a fleet-wide monitor
registry (`nixdisplay.monitors`, keyed by EDID identity — a panel roams between hosts) and named
output arrangements (`nixdisplay.layouts`). [nixdesktop](https://github.com/julian-corbet/nixdesktop-corbet-ch)
owns per-session device permission (`nixdesktop.sessions.<name>.permittedDevices`, the complement
of which is derived for niri — scroll needs only the allow-side). `programs.scroll.nixdesktop`
consumes all three, the same `lib.probeFact` way `startup` above does: never a flake input on
nixdisplay or nixdesktop, silent when they aren't composed at all — but naming a `layout` or
`session` that does not resolve to a real entry FAILS THE BUILD (an assertion, not a warning): a
request to arrange real monitors or claim a real device that silently does nothing is worse than
one that refuses to build.

```nix
programs.scroll.nixdesktop = {
  layout = "docked";   # a nixdisplay.layouts.<name> — renders as `output` blocks
  session = "primary"; # a nixdesktop.sessions.<name> — feeds permittedDrmDevices below
};
```

**`layout`** translates every enabled output in the named `nixdisplay.layouts.<name>` into this
module's own `output` directives — mode/modeline, scale, position, transform, enable/disable —
and, for an output matched by identity, one stanza per `aliases` variant (the same physical panel
presents a different EDID per input, and scroll matches only the literal string on the wire). This
is *additive* to the hand-written `outputs` attrset above, not a replacement for it: a host can
hand-tune one output and let the layout drive the rest.

Two measured facts this translation exists to get right, both silent failures if missed:

- **Rotation direction.** nixdisplay's `transform` vocabulary is counter-clockwise, matching
  `wl_output` itself. scroll (a sway fork) calls `invert_rotation_direction()` on every parse, so
  a bare pass-through would rotate a monitor 180° from what was asked for — and `swaymsg`/`scrollmsg`
  report the config's own spelling back, so the bug is invisible from IPC. This module inverts
  90↔270 and flipped-90↔flipped-270 (the other four values are their own inverse) in one named
  helper, so the swap can't be duplicated wrongly a second time.
- **A plain `mode` needs a literal `Hz` suffix — and it is plain `mode`, never `mode --custom`.**
  Verified against the real binary: `mode 1920x1080@60` is rejected, `mode 1920x1080@60Hz` is
  accepted, and `mode 1920x1080` (no rate at all) is accepted unchanged. nixdisplay's neutral `mode`
  string carries no Hz requirement, so this module normalises it. `--custom` was tried first and is
  wrong: it names an unlisted/custom *modeline*, not "a mode typed by hand", and scroll accepts a
  plain "WIDTHxHEIGHT[@RATE]" mode without it. A raw `modeline` (the option nixdisplay's own layout
  module carries specifically for panels — an ASPEED ast2500 BMC framebuffer in this estate's case —
  that only accept one sync polarity, which no named mode can express) is scroll's actual
  custom-mode path, and is passed through to scroll's own `modeline` directive verbatim.

**`session`** feeds `programs.scroll.nixdesktop.permittedDrmDevices`, a read-only, always-derived
list of real `/dev/dri/by-path/*-card` *paths* — never bare device names. Each name in
`nixdesktop.sessions.<name>.permittedDevices` is resolved, at eval time, against
`nixgpu.stableDevicePaths.devices.<name>.cardPath`: a PCI domain:bus:device.function or platform
device name is a physical slot fixed at build/install time, not a probe-order artifact like
`/dev/dri/cardN` or a DRM minor (which DO renumber between boots — an evdi load reshuffled this
estate's own host on 2026-07-29), so unlike those, the path is genuinely knowable and stable at
eval time. This is a reversal from an earlier version of this option that emitted device *names*
and deferred resolution to whatever started the session: that shape measurably breaks twice over —
a `DevicePolicy=strict` systemd unit deadlocks the instant an `ExecStartPre` tries to populate
`DeviceAllow=` from inside its own already-restricted cgroup, and niri's sibling compositor module
cannot resolve a name at all, because niri reads its config from disk, never a launcher's
environment — a name-based restriction there is a valid config that enforces nothing. Ordered
primary-first, exactly as `nixdesktop.sessions.<name>.permittedDevices` orders it, because wlroots
takes the *first* device in `WLR_DRM_DEVICES` that successfully opens as the primary. A name absent
from `nixgpu.stableDevicePaths.devices` is dropped from the list rather than thrown.

`checks/layout-outputs.nix` proves the translation directly (transform inversion for every value,
identity-with-spaces quoting, alias fan-out, a disabled output rendering only `disable`, an
unresolvable `layout`/`session` name failing the build, and `permittedDrmDevices` resolving to
`nixgpu`'s stable paths); the identity, modeline and transform cases are also run through
`checks/config-accepted.nix`'s real-binary gate.
