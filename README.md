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
