{
  description = "nixscroll — declarative config generation for scroll (a scrolling/PaperWM-style fork of sway), plus the packaging and system wiring it needs since it isn't in nixpkgs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # scroll (github.com/dawsers/scroll) is NOT in nixpkgs, and this repo does not attempt to
    # package it itself. github:Diax170/scroll-flake is the maintained, working packaging for it
    # (overlays nixpkgs' own sway-unwrapped build with scroll's source — the same meson/wlroots
    # build sway already uses, just pointed at a different tree). Taking it as a flake INPUT and
    # passing the package straight through (see `packages.<system>.scroll` below) is a deliberate,
    # documented exception to this family's usual single-nixpkgs-input rule: scroll has no home in
    # nixpkgs for a `nixosModules.backend`-style module here to build against, so without this
    # input every consumer of this repo would have to go solve scroll packaging on their own before
    # `homeManagerModules.scroll` (config generation) or `nixosModules.scroll` (system install) had
    # anything to point at. Full credit to Diax170 for the packaging — see README.
    scroll-flake = {
      url = "github:Diax170/scroll-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixhost IS an input, for exactly one thing: `lib.probeFact` (github:julian-corbet/
    # nixhost-corbet-ch, `lib/facts.nix`) -- the shared, plain-function fix for the
    # cross-namespace defensive-read defect class `home/scroll.nix`'s own
    # `nixdesktopStartupProbe` leans on (see nixhost's own `lib/facts.nix` header).
    # `probeFact` is closed over as a plain function argument (below), never `_module.args`, so
    # a consumer importing `homeManagerModules.scroll` sees an ordinary module function and never
    # needs to know `nixhost` exists. This is unrelated to how `nixdesktop.startup` itself is
    # read: that stays a defensive, zero-flake-dependency probe -- only the `probeFact`
    # MECHANISM is consumed from nixhost.
    nixhost = {
      url = "github:julian-corbet/nixhost-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, scroll-flake, nixhost }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      # `probeFact` closed over here, before the module system ever sees the result -- see the
      # `nixhost` input comment above. The exported value is a plain home-manager module function
      # taking the usual `{ lib, config, ... }`; nothing about consuming it changes.
      scrollModule = import ./home/scroll.nix { inherit (nixhost.lib) probeFact; };
    in
    {
      # ── PACKAGING (passthrough, see the input comment above) ────────────────────────────────
      packages = forAllSystems (system: {
        scroll = scroll-flake.packages.${system}.default;
        default = scroll-flake.packages.${system}.default;
      });

      # ── SYSTEM SIDE ───────────────────────────────────────────────────────────────────────
      # Thin on purpose: installs the package and registers the wayland-sessions entry it ships,
      # nothing more. Config generation (below) is a separate, optional concern — a consumer who
      # only wants scroll launchable from a display manager, with scroll's own upstream default
      # config, needs only this module.
      nixosModules.scroll = import ./modules/nixos.nix { inherit self; };
      nixosModules.default = self.nixosModules.scroll;

      # Arch/CachyOS plane. scroll is not in nixpkgs, so unlike niri it cannot be resolved through
      # nixdesktop's role table -- on NixOS this repo's own package output fills that gap, and on
      # Arch the AUR package does. Declares the name into nixarch.packages.aur; nixarch's
      # reconciler installs it. Config generation stays in homeManagerModules.scroll on both.
      systemManagerModules.scroll = ./modules/system-manager.nix;
      systemManagerModules.default = self.systemManagerModules.scroll;

      # ── CONFIG GENERATION ────────────────────────────────────────────────────────────────
      # Writes ~/.config/scroll/config from structured options (namespace: programs.scroll).
      # Installs nothing — see README. Reads no package by default; the one place it optionally
      # does (see `package` option in home/scroll.nix) never adds anything to home.packages.
      homeManagerModules = {
        scroll = scrollModule;
        default = scrollModule;
      };

      # ── CHECKS ────────────────────────────────────────────────────────────────────────────
      # `nix flake check` does NOT evaluate `homeManagerModules` or `systemManagerModules` — it
      # lists them as unchecked and moves on. Since config generation is what this repo is FOR,
      # a green `flake check` here covered the package passthrough and the NixOS module while
      # proving nothing at all about home/scroll.nix. This closes that gap by evaluating the module
      # for real against a minimal home-manager stub.
      #
      # Scoped to the `nixdesktop.startup` seam rather than being a full golden-file test of the
      # rendered config: the seam is the part with a SILENT failure mode (a populated contract with
      # no reader renders nothing and errors nowhere), and silent failures are what a check earns
      # its keep on.
      #
      # A malformed bindsym does NOT surface the moment scroll starts: scroll logs a rejected
      # directive to stderr and carries on, both at startup and under `--validate`, which exits 0
      # regardless. A bad directive surfaces nowhere unless something greps for it -- which is
      # why `config-accepted` below exists.
      checks = forAllSystems (system: {
        startup-contract = import ./checks/startup-contract.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit scrollModule;
        };
        # Runs the REAL binary against this module's own output. Everything else here is Nix
        # inspecting Nix, which cannot notice that scroll disagrees -- and it did, about ten
        # directives. See the check's header for why it greps stderr instead of trusting the
        # exit code, and note this is the one check that costs a scroll build.
        config-accepted = import ./checks/config-accepted.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          scroll = self.packages.${system}.scroll;
          inherit scrollModule;
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
