# nixscroll

Declarative config generation for [scroll](https://github.com/dawsers/scroll) — a fork of
[sway](https://github.com/swaywm/sway) with a scrolling, PaperWM-style tiling layout — plus the
packaging and system wiring scroll needs since, unlike sway, it isn't in nixpkgs. Three outputs:
a package passthrough, a home-manager module that writes `~/.config/scroll/config` from
structured options, and a thin NixOS module for the system side.

## The split

Three pieces, because scroll not being in nixpkgs is a real constraint that shapes the whole repo:

**Packaging** (`packages.<system>.scroll`) — a straight passthrough of
[Diax170/scroll-flake](https://github.com/Diax170/scroll-flake)'s own `packages.<system>.default`.
This repo does not package scroll itself. Taking scroll-flake as a flake input and re-exporting
its package is a deliberate exception to the usual rule of pinning exactly one `nixpkgs` and
nothing else — see the comment at the top of [`flake.nix`](flake.nix) for the full reasoning.
Full credit to [Diax170](https://github.com/Diax170) for the actual packaging work (an overlay
that patches nixpkgs' own `sway-unwrapped` build to compile scroll's source instead); this repo
only forwards it.

**Config generation** (`homeManagerModules.scroll`, namespace `programs.scroll`) — a home-manager
module that renders `~/.config/scroll/config` from a structured option tree instead of hand-edited
sway-syntax text. Installs nothing: it assumes a `scroll` binary exists somewhere on `$PATH` (or
gets installed by the NixOS module below, or by hand, or by a distro package) and writes config
for it. This is the module most consumers want.

**System install** (`nixosModules.scroll`, same `programs.scroll` namespace) — installs the
package and registers scroll as a selectable wayland-sessions entry for a display manager. Kept
deliberately thin — no wrapper features, no XDG portal config, no extra packages. If you want
that fuller sway.nix-style module, scroll-flake ships its own `nixosModules.default` under this
same namespace; use one or the other, not both, since they'd both try to own `programs.scroll`.

Neither the config-generation module nor the NixOS module invents its own option namespace per
project convention — both use `programs.scroll`, matching how nixpkgs itself names
`programs.sway` and how scroll-flake already named its own NixOS module, so the same mental model
(and, for the NixOS side, literally the same option path) carries over.

## Modules

| Output | Class | Owns |
|---|---|---|
| `packages.<system>.scroll` | flake package | passthrough of `Diax170/scroll-flake`'s `packages.<system>.default` |
| `homeManagerModules.scroll` (`.default`) | home-manager | `~/.config/scroll/config`, generated from `programs.scroll.*`. Installs nothing. |
| `nixosModules.scroll` (`.default`) | NixOS | `environment.systemPackages` + `services.displayManager.sessionPackages` for `programs.scroll.package` |

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
niri-based CPU-rendered desktop) and [nixremote](https://github.com/julian-corbet/nixremote-corbet-ch)
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
`config.nixdesktop.startup` defensively (`or [ ]`) and emits each entry as its own `exec` line,
ordered ahead of anything you put in `programs.scroll.startup` — contract entries are session
components a host's own commands may expect to be running already.

If no nixdesktop module is in scope at all, the read yields an empty list and nothing extra is
rendered. No flake input on nixdesktop is involved, and none is needed; this is the same
defensive-read idiom nixboot uses for `nixstorage.layout` and nixhost uses for the facts it mirrors.
The dependency stays one-way: nixdesktop declares the contract and knows nothing about scroll.

> **This used to be your job, and it was a trap.** Earlier versions asked you to write
> `programs.scroll.startup = config.nixdesktop.startup;` yourself, on the stated grounds that a
> compositor module *cannot* read an option from a repo it does not depend on. That premise was
> simply wrong — a defensive read needs no dependency. The cost of believing it was a silent
> failure mode: forget the line and the component is fully configured, its files written, and it
> never launches, with no error possible, because a populated list with no reader is a valid
> configuration. `checks/startup-contract.nix` now asserts the splice in both directions, since
> `nix flake check` does not evaluate `homeManagerModules` and so never covered this at all.

`programs.scroll.startup` remains yours for the host's own commands, and still takes bare commands
rather than raw config lines. (niri's native startup syntax takes raw KDL, so nixniri translates the
same neutral list into `spawn-sh-at-startup` lines instead — each compositor module adapts the
contract to its own syntax, which is the point of the contract being neutral.)
