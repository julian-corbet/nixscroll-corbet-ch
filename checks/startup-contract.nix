# Evaluates home/scroll.nix for real, and asserts the `nixdesktop.startup` seam works BOTH ways.
#
# WHY THIS FILE EXISTS AT ALL: `nix flake check` does not evaluate `homeManagerModules` (nor
# `systemManagerModules`). It reports them as "unchecked" and moves on, so a green check here
# covered the package passthrough and the NixOS module and nothing else -- the config generator,
# which is the thing this repo is actually for, could fail to evaluate or render the wrong text and
# CI would still pass. That blind spot is how the startup contract came to have one producer
# (nixdesktop's noctalia module) and zero consumers for as long as it did.
#
# The stub below is a deliberately minimal stand-in for the home-manager options this module writes
# to, not an attempt to reimplement home-manager: the point is to exercise THIS module's logic, and
# a full home-manager instantiation would add a large dependency without covering any more of the
# thing under test.
{ pkgs, lib ? pkgs.lib }:
let
  stubs = { lib, ... }: {
    options = {
      xdg.configFile = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
      };
      home.packages = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      home.file = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      systemd.user = lib.mkOption { type = lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  # The neutral contract, declared the way nixdesktop declares it and populated the way a
  # nixdesktop component populates it. One entry deliberately carries a flag, since contract
  # entries are shell command strings rather than argv lists.
  contract = { lib, ... }: {
    options.nixdesktop.startup = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    config.nixdesktop.startup = [ "noctalia-shell -d" "some-agent --flag" ];
  };

  render = extra: (lib.evalModules {
    modules = [ stubs ../home/scroll.nix { programs.scroll.enable = true; } ] ++ extra;
    specialArgs = { inherit pkgs; };
  }).config.xdg.configFile."scroll/config".text;

  withContract = render [ contract ];
  withoutContract = render [ ];

  # With a host ALSO declaring its own startup command, so ordering can be asserted.
  withBoth = render [ contract { programs.scroll.startup = [ "host-own-command" ]; } ];

  has = haystack: needle: lib.hasInfix needle haystack;

  # Index of the first line containing `needle`, or null. Written out rather than reached for in
  # lib because the exact helper name for this has moved around between nixpkgs releases, and this
  # check should not break on a nixpkgs bump.
  lineIndexOf = text: needle:
    let
      lines = lib.splitString "\n" text;
      hits = lib.filter (i: has (builtins.elemAt lines i) needle)
        (lib.range 0 (builtins.length lines - 1));
    in
    if hits == [ ] then null else builtins.head hits;

  results = {
    # POSITIVE — contract entries reach the rendered config as scroll/sway `exec` lines.
    "contract entry renders as an exec line" =
      has withContract "exec noctalia-shell -d";
    "a contract entry carrying a flag survives intact" =
      has withContract "exec some-agent --flag";

    # NEGATIVE — with NO nixdesktop module in scope at all, this module must still evaluate (that
    # `withoutContract` is a string at all proves it) and must render none of the contract.
    "evaluates and renders nothing extra when nixdesktop is absent" =
      !(has withoutContract "noctalia-shell");

    # ORDERING — contract entries are session components (a bar, a notifier, a polkit agent) that a
    # host's own startup commands may reasonably expect to be running already, so the neutral list
    # renders first. Asserted rather than left to a comment, because it is invisible either way
    # until something races.
    "contract entries are ordered before the host's own startup commands" =
      let
        neutralAt = lineIndexOf withBoth "noctalia-shell";
        hostAt = lineIndexOf withBoth "host-own-command";
      in
      neutralAt != null && hostAt != null && neutralAt < hostAt;

    # NON-VACUITY — without this, an empty render would make every hasInfix check above pass
    # trivially and the whole file would be a very confident no-op.
    "both renders are real, non-empty configs" =
      lib.stringLength withoutContract > 100 && lib.stringLength withContract > 100;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.runCommand "nixscroll-startup-contract-ok" { } "touch $out"
else throw ''
  nixscroll: the nixdesktop.startup seam is broken. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
