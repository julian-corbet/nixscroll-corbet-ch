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
#
# The fact-wiring group at the bottom proves the SAME blind spot one layer deeper: `home/scroll.nix`
# reads `nixdesktop.startup` through `lib.probeFact` (consumed from nixhost's own `lib/facts.nix`
# via this repo's `nixhost` flake input, see flake.nix), which is the only thing that can ever
# tell "nixdesktop not composed at all" apart from "nixdesktop composed but `startup` itself
# renamed" -- both resolve to the identical empty list `startup`'s own real default already
# provides, so without this check a rename would be just as invisible as the original
# zero-consumers incident this file exists to prevent.
#
# `scrollModule` arrives here ALREADY partially applied (flake.nix closes `home/scroll.nix` over
# the real, locked `nixhost.lib.probeFact` before this check ever runs) -- this file never reaches
# for the raw `../home/scroll.nix` path itself, the same "consume the applied module, not the raw
# file" shape nixlxc/nixvm's own checks/default.nix use for `containersModule`/`guestsModule`.
{ pkgs, lib ? pkgs.lib, scrollModule }:
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

  # THE DECOY: nixdesktop's real option surface, renamed. Composes the SAME top-level
  # `nixdesktop` namespace the real sibling would (so `config ? nixdesktop` reads true -- state
  # (a), "not composed at all", must NOT be what this fixture exercises), with the specific path
  # `home/scroll.nix`'s own probe reads (`startup`) missing, renamed to a plausible neighbour --
  # proving state (c), composed-but-moved, actually warns through the real module.
  contractRenamed = { lib, ... }: {
    options.nixdesktop.autostart = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    config.nixdesktop.autostart = [ "noctalia-shell -d" ];
  };

  evalScroll = extra: (lib.evalModules {
    modules = [ stubs scrollModule { programs.scroll.enable = true; } ] ++ extra;
    specialArgs = { inherit pkgs; };
  }).config;

  render = extra: (evalScroll extra).xdg.configFile."scroll/config".text;
  warningsOf = extra: (evalScroll extra).warnings;

  withContract = render [ contract ];
  withoutContract = render [ ];

  # With a host ALSO declaring its own startup command, so ordering can be asserted.
  withBoth = render [ contract { programs.scroll.startup = [ "host-own-command" ]; } ];

  # ── fact-wiring: lib.probeFact proven THROUGH the real home/scroll.nix module ────────────
  warningsFaithful = warningsOf [ contract ];
  warningsNoNixdesktopAtAll = warningsOf [ ];
  warningsRenamed = warningsOf [ contractRenamed ];

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

    # ── fact-wiring: lib.probeFact (nixhost's own lib/facts.nix, consumed via this repo's
    # `nixhost` flake input) proven THROUGH this real module, not just against lib/facts.nix's
    # own function-level behaviour.
    # `nixdesktop.startup` has a genuine `[ ]` default, so a rename resolves to the identical
    # empty list a never-imported nixdesktop would -- both render fine, silently, with no error --
    # which is exactly the "populated list with no reader" failure mode this file's own header
    # describes, just one level further back: now the LIST ITSELF can go silently unreachable, not
    # only unread. The warning is the only thing that would ever tell anyone.
    "state (a) -- nixdesktop not composed at all -- produces no warnings" =
      warningsNoNixdesktopAtAll == [ ];

    "nixdesktop composed with its real, un-renamed shape produces no warnings" =
      warningsFaithful == [ ];

    "nixdesktop composed but startup renamed warns exactly once, naming the option" =
      lib.length warningsRenamed == 1
      && has (lib.head warningsRenamed) "nixdesktop.startup"
      && has (lib.head warningsRenamed) "nixdesktop";

    "a renamed nixdesktop still evaluates and renders nothing extra, never an error" =
      !(has (render [ contractRenamed ]) "noctalia-shell");
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
# `pkgs.emptyFile`, not `pkgs.runCommand "..." {} "touch $out"`: this check decides everything at
# EVALUATION time, so the derivation below is a pure formality that `nix flake check` requires
# anyway -- but `nix flake check --all-systems` (which this repo's own CI runs, and rightly: without
# it every non-runner system goes unevaluated while CI reports green) asks for that formality on
# EVERY declared system. `runCommand`'s output path is system-dependent, so the aarch64-linux
# marker becomes a REAL aarch64 build and dies with "platform mismatch" on an x86_64 runner --
# turning a passing test suite into a red check about nothing. `emptyFile` is fixed-output: its
# path comes from the content hash alone and is byte-identical on every system, so Nix substitutes
# it (or finds it already realised) instead of building it, anywhere. Same fix, same reason, as
# nixdesktop's `checks/support.nix`.
if failed == [ ]
then pkgs.emptyFile
else throw ''
  nixscroll: the nixdesktop.startup seam is broken. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
