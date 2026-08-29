# modules/nixos.nix — nixosModules.scroll: the system-install half of this repo's split (see
# flake.nix and README's "The split"). Config generation (~/.config/scroll/config) is a
# separate concern, handled entirely by homeManagerModules.scroll — this module never touches it.
#
# Kept deliberately narrow: install the runtime product and every required
# external component in cscroll's manifest, then register the wayland-sessions
# entry it ships. It carries no module-level wrapper options or
# default_decoration duplicate of what home-manager already owns — the
# package's fixed Mesa environment is separate. Diax170/scroll-flake's own
# `nixosModules.default` already implements the fuller sway.nix-style module (wrapper features,
# XDG portal config, extraPackages, ...) under this same `programs.scroll` namespace if a consumer
# wants that instead of this one.
# Use one or the other, not both — they'd fight over the same option tree.
{ self, runtimeManifest, ... }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.scroll;
  requiredExternal = lib.filter
    (component:
      component.required
      && component.kind != "bundled-command")
    runtimeManifest.component;
  companionPackages = map
    (component:
      let
        attribute = component.nixpkgs-package
          or (throw "nixscroll: component ${component.id} has no nixpkgs mapping");
      in
      pkgs.${attribute}
      or (throw "nixscroll: nixpkgs has no package named ${attribute} for component ${component.id}"))
    requiredExternal;
in
{
  options.programs.scroll = {
    enable = lib.mkEnableOption ''
      cscroll at the system level: installs the runtime product and all
      required external components from its manifest, then registers it as a
      selectable wayland-sessions entry for display managers
      (SDDM, gdm, ly, ...). Does not generate ~/.config/scroll/config — see
      homeManagerModules.scroll for that, or scroll's own upstream default config
      (/etc/scroll/config, shipped inside the package) if you generate nothing at all
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.scroll;
      defaultText = lib.literalExpression
        "nixscroll's own packages.<system>.scroll — cscroll built through Diax170/scroll-flake's recipe";
      example = lib.literalExpression
        "inputs.nixscroll.packages.<system>.scroll";
      description = ''
        The scroll package to install. scroll is not in nixpkgs, so unlike most NixOS
        module `package` options this one does not default to `pkgs.scroll` — see flake.nix.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ companionPackages;

    # Native NixOS mechanism (mirrors nixpkgs' own programs.sway/programs.wayfire, etc): a
    # package's own build declares which sessions it provides — the scroll-flake recipe
    # sets `passthru.providedSessions = [ "scroll" ]` on top of the sway-unwrapped derivation it
    # patches, and the same sway-derived meson build already installs
    # share/wayland-sessions/scroll.desktop as a result. sessionPackages links that into the
    # system profile so display managers list "scroll" as a session — nothing here hand-writes
    # a .desktop entry that could drift from what the package actually ships.
    services.displayManager.sessionPackages = [ cfg.package ];
  };
}
