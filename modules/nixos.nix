# modules/nixos.nix — nixosModules.scroll: the system-install half of this repo's split (see
# flake.nix and README's "The split"). Config generation (~/.config/scroll/config) is a
# separate concern, handled entirely by homeManagerModules.scroll — this module never touches it.
#
# Kept deliberately thin: install the package, register the wayland-sessions entry it ships.
# That's it. No wrapperFeatures, no extraSessionCommands, no default_decoration duplicate of
# what home-manager already owns — Diax170/scroll-flake's own `nixosModules.default` already
# implements the fuller sway.nix-style module (wrapper features, XDG portal config, extraPackages,
# ...) under this same `programs.scroll` namespace if a consumer wants that instead of this one.
# Use one or the other, not both — they'd fight over the same option tree.
{ self, ... }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.scroll;
in
{
  options.programs.scroll = {
    enable = lib.mkEnableOption ''
      scroll (a scrolling/PaperWM-style fork of sway) at the system level: installs the
      package and registers it as a selectable wayland-sessions entry for display managers
      (SDDM, gdm, ly, ...). Does not generate ~/.config/scroll/config — see
      homeManagerModules.scroll for that, or scroll's own upstream default config
      (/etc/scroll/config, shipped inside the package) if you generate nothing at all
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.scroll;
      defaultText = lib.literalExpression
        "nixscroll's own packages.<system>.scroll — a passthrough of Diax170/scroll-flake's packages.<system>.default (see flake.nix's input comment for why scroll is packaged upstream rather than here)";
      example = lib.literalExpression
        "inputs.scroll-flake.packages.<system>.scroll-git # bleeding-edge build, bypassing this repo's passthrough entirely";
      description = ''
        The scroll package to install. scroll is not in nixpkgs, so unlike most NixOS
        module `package` options this one does not default to `pkgs.scroll` — see flake.nix.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Native NixOS mechanism (mirrors nixpkgs' own programs.sway/programs.wayfire, etc): a
    # package's own build declares which sessions it provides — Diax170/scroll-flake's overlay
    # sets `passthru.providedSessions = [ "scroll" ]` on top of the sway-unwrapped derivation it
    # patches, and the same sway-derived meson build already installs
    # share/wayland-sessions/scroll.desktop as a result. sessionPackages links that into the
    # system profile so display managers list "scroll" as a session — nothing here hand-writes
    # a .desktop entry that could drift from what the package actually ships.
    services.displayManager.sessionPackages = [ cfg.package ];
  };
}
