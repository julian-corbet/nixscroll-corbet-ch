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
  };

  outputs = { self, nixpkgs, scroll-flake }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
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

      # ── CONFIG GENERATION ────────────────────────────────────────────────────────────────
      # Writes ~/.config/scroll/config from structured options (namespace: programs.scroll).
      # Installs nothing — see README. Reads no package by default; the one place it optionally
      # does (see `package` option in home/scroll.nix) never adds anything to home.packages.
      homeManagerModules = {
        scroll = ./home/scroll.nix;
        default = ./home/scroll.nix;
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
