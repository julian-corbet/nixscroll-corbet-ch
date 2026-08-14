# checks/virtual-outputs.nix — evaluates home/scroll.nix for real and proves the
# nixdesktop.sessions.<name>.virtualOutputs -> scroll's create_output/output-mode IPC translation
# (home/scroll.nix's own `virtualOutputLines`): the HEADLESS-<N+1> numbering offset scroll's own
# FALLBACK output forces on every process it runs (seated or headless alike), the exact
# `create_output; output "..." mode WxH` command text `scrollmsg` receives as ONE argument (never
# two separate `exec` lines racing each other), one exec line per declared virtual output in
# declaration order, and the silent-nothing states (no session named, an empty virtualOutputs
# list) that must render no such line at all rather than a stray empty one.
#
# WHY THIS IS ITS OWN FILE rather than folded into checks/layout-outputs.nix (which already
# proves the SIBLING nixdisplay.layouts/nixdisplay.monitors translation): a virtual output has no
# monitor identity and no physical position — see modules/session.nix's own `virtualOutputs`
# doc — so it shares nothing with layout-outputs.nix's fixtures (a `nixdisplay.monitors` table, an
# identity matcher, an overlap-adjacent position) beyond both ultimately rendering output-related
# commands. Keeping the two apart means a failure here names the concern precisely.
#
# WHY THE REAL SOURCE-READING IN home/scroll.nix'S OWN COMMENT MATTERS TO THIS FILE: the
# HEADLESS-<N+1> offset is not a convention this repo invented, it is a measured fact about
# `sway/server.c` and `backend/headless/output.c` in the real dawsers/scroll source (this repo's
# own package input). Getting it wrong here would mean this check and the module it is checking
# share the SAME wrong assumption and agree with each other for the wrong reason — which is
# exactly why `checks/config-accepted.nix` also carries a virtualOutputs fixture through the REAL
# binary: this file proves the module renders what it INTENDS, that one proves scroll accepts the
# resulting `exec` line as valid config syntax at all.
{ pkgs, lib ? pkgs.lib, scrollModule }:
let
  stubs = { lib, ... }: {
    options = {
      xdg.configFile = lib.mkOption { type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything); default = { }; };
      home.packages = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      home.file = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      systemd.user = lib.mkOption { type = lib.types.anything; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  # A `nixdesktop.sessions` stand-in, narrowed to exactly the two leaves this module's
  # `virtualOutputLines`/`permittedDrmDevices` read — same doctrine as checks/layout-outputs.nix's
  # own `withSession` (never the real nixdesktop module tree, see that file's header for why).
  withSession = extra: { lib, ... }: {
    options.nixdesktop.sessions = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    config = {
      nixdesktop.sessions.primary = { permittedDevices = [ ]; deniedDevices = [ ]; virtualOutputs = [ ]; } // extra;
      programs.scroll.nixdesktop.session = "primary";
    };
  };

  evalScroll = extra: (lib.evalModules {
    modules = [ stubs scrollModule { programs.scroll.enable = true; } ] ++ extra;
    specialArgs = { inherit pkgs; };
  }).config;

  render = extra: (evalScroll extra).xdg.configFile."scroll/config".text;

  has = haystack: needle: lib.hasInfix needle haystack;

  oneOutput = render [ (withSession { virtualOutputs = [{ width = 1920; height = 1080; }]; }) ];
  twoOutputs = render [
    (withSession {
      virtualOutputs = [
        { width = 1920; height = 1080; }
        { width = 2560; height = 1440; }
      ];
    })
  ];
  noOutputsDeclared = render [ (withSession { virtualOutputs = [ ]; }) ];
  noSessionNamedAtAll = render [ ];

  results = {
    # ── THE FALLBACK OFFSET — THE FACT MOST LIKELY TO BE SILENTLY WRONG ─────────────────────
    # scroll's own server_init() spends HEADLESS-1 on a "FALLBACK" output nobody asked for,
    # before this module's own exec lines ever run (see home/scroll.nix's `virtualOutputLines`
    # comment, citing sway/server.c and backend/headless/output.c directly) — so the FIRST
    # virtual output this module creates must be addressed as HEADLESS-2, never HEADLESS-1.
    "the first declared virtual output is addressed as HEADLESS-2, never HEADLESS-1" =
      has oneOutput ''output "HEADLESS-2" mode 1920x1080''
      && !(has oneOutput "HEADLESS-1");

    "a second declared virtual output is addressed as HEADLESS-3, in declaration order" =
      has twoOutputs ''output "HEADLESS-2" mode 1920x1080''
      && has twoOutputs ''output "HEADLESS-3" mode 2560x1440'';

    # ── ONE scrollmsg CALL PER OUTPUT, create_output CHAINED WITH ITS OWN mode ──────────────
    # Two separate `exec` lines would fork two independent processes with no ordering guarantee
    # between them (see home/scroll.nix's own comment) — proving this is ONE exec line, ONE
    # scrollmsg argument, is what rules that race out.
    # A plain double-quoted string here, deliberately, not an indented `''...''` one: the content
    # ends in a literal `'` immediately before the string's own closing quotes, and THREE
    # consecutive `'` in an indented string is Nix's OWN escape sequence for a literal `''` (see
    # the Nix manual on indented strings) -- it does not close the string at all, and the parser
    # keeps consuming everything after as string content until it stumbles on something that
    # breaks it much later in the file. Measured directly: the first version of this line was
    # written as an indented string and broke `nix-instantiate --parse` with an error pointing at
    # the unrelated `throw` message near the bottom of this file, not at the real defect here.
    "create_output and its mode line are ONE scrollmsg argument on ONE exec line, not two" =
      has oneOutput "exec scrollmsg 'create_output; output \"HEADLESS-2\" mode 1920x1080'"
      && lib.length (lib.filter (l: has l "create_output") (lib.splitString "\n" oneOutput)) == 1;

    # `create_output` is scroll's own "Runtime-only" IPC command (see home/scroll.nix's comment) —
    # it must never be emitted as a bare, static `output "HEADLESS-N" ...` config block, which
    # could only ever configure an output that already exists.
    "create_output is never emitted as a bare config directive, only inside the exec/scrollmsg line" =
      let
        lines = lib.filter (l: has l "HEADLESS-2") (lib.splitString "\n" oneOutput);
      in
      lib.all (l: has l "exec scrollmsg") lines;

    # ── SILENT-NOTHING STATES ─────────────────────────────────────────────────────────────────
    "an empty virtualOutputs list renders no create_output line at all" =
      !(has noOutputsDeclared "create_output");

    "no nixdesktop.session named renders no create_output line at all" =
      !(has noSessionNamedAtAll "create_output");
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
# `pkgs.emptyFile`, not `pkgs.runCommand "..." {} "touch $out"` — same reasoning as
  # checks/layout-outputs.nix and checks/startup-contract.nix: this check decides everything at
  # evaluation time, and a system-dependent marker becomes a real foreign-arch build under
  # `nix flake check --all-systems`.
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixscroll: the nixdesktop.sessions.<name>.virtualOutputs -> create_output translation is wrong.
    Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
