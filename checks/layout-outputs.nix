# checks/layout-outputs.nix — evaluates home/scroll.nix for real and proves the
# nixdesktop.layouts/nixdesktop.monitors/nixdesktop.sessions translation this repo owns: transform
# inversion (the single fact most likely to be silently wrong, and invisible from IPC on this exact
# compositor — sway inverts back when reporting, see modules/layouts.nix's own `transform` option
# upstream in nixdesktop), an identity matcher with embedded spaces round-tripping quoted, one
# stanza per alias variant, a disabled output rendering ONLY scroll's own `disable` directive (no
# mode/scale/position/transform alongside it — matching nixniri's own `renderOutputBlock` short
# circuit), an unresolvable `layout`/`session` name FAILING THE BUILD rather than rendering nothing
# with no error, and `permittedDrmDevices` resolving to real `/dev/dri/by-path/*` paths via
# `nixgpu.stableDevicePaths.devices` rather than to the bare device names it used to pass through.
#
# WHY THIS FILE EXISTS AT ALL: the same reason `checks/startup-contract.nix` does — `nix flake
# check` does not evaluate `homeManagerModules`, so a green check here would otherwise prove
# nothing about this repo's one actual translation layer, which is exactly the kind of derived
# arithmetic that fails silently rather than loudly (a matcher that matches nothing is not an
# error on either compositor, see modules/monitors.nix upstream).
#
# The stub below composes a MINIMAL stand-in for `nixdesktop.layouts`/`nixdesktop.monitors`/
# `nixdesktop.sessions` and for `nixgpu.stableDevicePaths.devices`, not either sibling repo's own
# real modules — pulling either in as a path dependency would give this repo an undeclared coupling
# to a sibling repo's internals, which is precisely what `lib.probeFact` exists to avoid. Each
# stand-in only needs to carry the same SHAPE the real modules resolve to (`identifier`/
# `aliases.*.identifier` on a monitor; `monitor`/`connector`/`match`/`enable`/`mode`/`modeline`/
# `scale`/`position`/`transform` on a layout output; `permittedDevices` on a session; `address`/
# `cardPath`/`renderPath` on a nixgpu device entry).
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

  # One layout named "desk", holding whatever `outputs` a fixture supplies, plus whichever
  # `monitors` entries its outputs need to resolve identity matching — and the selection itself
  # (`programs.scroll.nixdesktop.layout = "desk"`), so every fixture below is a single self
  # contained module rather than three things a caller must remember to wire together.
  withLayout = outputs: monitors: { lib, ... }: {
    options.nixdesktop = {
      layouts = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      monitors = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    };
    config = {
      nixdesktop.layouts.desk = { description = "fixture"; inherit outputs; };
      nixdesktop.monitors = monitors;
      programs.scroll.nixdesktop.layout = "desk";
    };
  };

  evalScroll = extra: (lib.evalModules {
    modules = [ stubs scrollModule { programs.scroll.enable = true; } ] ++ extra;
    specialArgs = { inherit pkgs; };
  }).config;

  render = extra: (evalScroll extra).xdg.configFile."scroll/config".text;

  has = haystack: needle: lib.hasInfix needle haystack;

  # The estate's real Dell, exactly as modules/monitors.nix's own fixtures spell it, WITH the
  # `identifier`/`aliases` fields already resolved — this stub stands in for the derived output
  # of nixdesktop's own module, not for its input.
  dell = {
    make = "Dell Inc.";
    model = "DELL U4323QE";
    serial = "9BQR2P3";
    identifier = "Dell Inc. DELL U4323QE 9BQR2P3";
    aliases = [ ];
  };
  dellWithAlias = dell // {
    aliases = [{ identifier = "Dell Inc. DELL U4323QE (USB-C) 9BQR2P3"; }];
  };

  # A complete output entry, matching modules/layouts.nix's own output submodule shape field for
  # field, with every optional left at its neutral/off value — each fixture below overrides only
  # the one or two fields its own behaviour needs, so a test failure names the field that matters.
  base = {
    monitor = "dell";
    connector = null;
    match = "identity";
    enable = true;
    mode = null;
    modeline = null;
    scale = null;
    position = null;
    transform = "normal";
  };

  transformCfg = t: render [ (withLayout [ (base // { transform = t; }) ] { dell = dell; }) ];
  identityCfg = render [ (withLayout [ base ] { dell = dell; }) ];
  aliasCfg = render [ (withLayout [ base ] { dell = dellWithAlias; }) ];
  disabledCfg = render [ (withLayout [ (base // { enable = false; }) ] { dell = dell; }) ];

  # Every non-transform field ALSO set on the disabled entry, so "a disabled output renders only
  # `disable`" is proven against a fixture that would otherwise have something to leak, not one
  # (like `disabledCfg` above, whose mode/scale/position are all already null) that would pass the
  # same check by coincidence.
  richDisabledCfg = render [
    (withLayout
      [ (base // {
          enable = false;
          mode = "1920x1080@60";
          scale = 1.5;
          position = { x = 1920; y = 0; };
          transform = "90";
        })
      ]
      { dell = dell; })
  ];

  # `connector` matching needs no monitor table entry at all, which is its own fixture, written
  # out fully rather than merged with `base` (whose `monitor = "dell"` would otherwise leave a
  # dangling, unused reference in the fixture).
  connectorOnlyCfg = render [
    (withLayout
      [{
        monitor = null;
        connector = "DP-1";
        match = "connector";
        enable = true;
        mode = null;
        modeline = null;
        scale = null;
        position = null;
        transform = "normal";
      }]
      { })
  ];

  # A stand-in for `nixgpu.stableDevicePaths.devices` -- see this file's header for why the real
  # module is never imported here. `cardPath`/`renderPath` are given as plain, already-resolved
  # strings (this file is not proving nixgpu's own `address` -> `cardPath` derivation, only that
  # nixscroll reads `cardPath` off whatever nixgpu resolves to), except `noAddress`, whose
  # `cardPath` is a bare `throw` -- reproducing the REAL nixgpu module's own lazy-throw behaviour
  # for a device declared with no `address` (a legitimate state per nixgpu's own option docs: "an
  # inventory that only needs the pre-existing by-vendor/by-driver symlinks never has to state
  # this"), so `drmCardPathOf`'s `tryEval` is proven against the actual failure shape, not a
  # stand-in that merely returns null where nixgpu would throw.
  withNixgpuDevices = devices: { lib, ... }: {
    # `attrsOf unspecified`, deliberately NOT `attrsOf anything`: `types.anything`'s own merge
    # recursively type-introspects every leaf of every value under it (calling `builtins.typeOf`
    # to decide how to merge) -- which FORCES `noAddress.cardPath`'s `throw` the moment the module
    # system merges this option at all, regardless of whether `drmCardPathOf` ever reads it. That
    # is a property of `anything`'s merge algorithm, not of reading an attribute -- it fired before
    # `builtins.tryEval` in `drmCardPathOf` ever got a chance to run, measured directly against
    # this stub. `unspecified` has no custom merge and falls back to a plain per-key passthrough
    # (`mergeDefaultOption`), so each device record here is carried as one opaque value, exactly
    # like the real nixgpu module's own `types.submodule` per-device option (lazy per-attribute,
    # never decomposed by the merge machinery itself) -- the shape this test needs to prove
    # `tryEval` against the real failure mode rather than against an artifact of the stub's typing.
    options.nixgpu.stableDevicePaths.devices = lib.mkOption { type = lib.types.attrsOf lib.types.unspecified; default = { }; };
    config.nixgpu.stableDevicePaths.devices = devices;
  };

  nixgpuDevices = {
    amd = {
      bus = "pci";
      address = "0000:0a:00.0";
      cardPath = "/dev/dri/by-path/pci-0000:0a:00.0-card";
      renderPath = "/dev/dri/by-path/pci-0000:0a:00.0-render";
    };
    evdi0 = {
      bus = "platform";
      address = "evdi.0";
      cardPath = "/dev/dri/by-path/platform-evdi.0-card";
      renderPath = null;
    };
    noAddress = {
      bus = "pci";
      address = null;
      cardPath = throw "nixgpu.stableDevicePaths.devices.noAddress.cardPath was read, but this device declares no address";
      renderPath = null;
    };
  };

  withSession = permittedDevices: { lib, ... }: {
    options.nixdesktop.sessions = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    config = {
      nixdesktop.sessions.primary = { inherit permittedDevices; deniedDevices = [ ]; };
      programs.scroll.nixdesktop.session = "primary";
    };
  };

  results = {
    # ── TRANSFORM INVERSION, every value the type admits ─────────────────────────────────────
    # scroll/sway is CLOCKWISE, nixdesktop's neutral vocabulary is COUNTER-CLOCKWISE — see
    # `invertTransform`'s own comment in home/scroll.nix. Each pair below proves both that the
    # correct value appears AND that the wrong (un-inverted) one does not, since a transform check
    # that only greps for the right string would pass just as happily if BOTH were emitted.
    "normal passes through unchanged" = has (transformCfg "normal") "transform normal";
    "180 passes through unchanged" = has (transformCfg "180") "transform 180";
    "flipped passes through unchanged" = has (transformCfg "flipped") "transform flipped";
    "flipped-180 passes through unchanged" = has (transformCfg "flipped-180") "transform flipped-180";
    "90 inverts to 270" =
      has (transformCfg "90") "transform 270" && !(has (transformCfg "90") "transform 90\n");
    "270 inverts to 90" =
      has (transformCfg "270") "transform 90" && !(has (transformCfg "270") "transform 270");
    "flipped-90 inverts to flipped-270" =
      has (transformCfg "flipped-90") "transform flipped-270"
      && !(has (transformCfg "flipped-90") "transform flipped-90");
    "flipped-270 inverts to flipped-90" =
      has (transformCfg "flipped-270") "transform flipped-90"
      && !(has (transformCfg "flipped-270") "transform flipped-270");

    # ── IDENTITY MATCHER ROUND-TRIPS QUOTED ─────────────────────────────────────────────────
    # An unquoted space-bearing identity is a SILENT misparse on the real binary (see quoteName's
    # own header in home/scroll.nix), not a build failure, so this is worth proving explicitly
    # rather than trusting `renderOutput`'s own quoting to be reused correctly.
    "an identity with embedded spaces is emitted quoted" =
      has identityCfg ''output "Dell Inc. DELL U4323QE 9BQR2P3"'';

    # ── ALIAS VARIANTS ───────────────────────────────────────────────────────────────────────
    "the monitor's own identity produces a block" =
      has aliasCfg ''output "Dell Inc. DELL U4323QE 9BQR2P3"'';
    "the alias's identity produces its OWN separate block too" =
      has aliasCfg ''output "Dell Inc. DELL U4323QE (USB-C) 9BQR2P3"'';

    # ── A DISABLED OUTPUT RENDERS ONLY `disable` ─────────────────────────────────────────────
    # nixniri's own `renderOutputBlock` is `if !o.enable then [ "off" ] else [...]` -- a short
    # circuit, not a filter applied after the fact. Two translators of one neutral vocabulary
    # rendering the SAME `enable = false` entry should not gratuitously disagree about what else
    # gets emitted for it, so this module's own disabled branch must be the same kind of
    # short-circuit, proven here against a fixture (`richDisabledCfg`) that sets mode/scale/
    # position/transform to real, non-null values specifically so there is something to leak.
    "enable = false renders scroll's own disable directive" =
      has disabledCfg ''output "Dell Inc. DELL U4323QE 9BQR2P3" disable'';
    "an enabled output emits no disable line at all" =
      !(has identityCfg "disable");
    "a disabled output renders ONLY disable -- mode/scale/position/transform are all suppressed, not merely absent because they happened to be null" =
      has richDisabledCfg ''output "Dell Inc. DELL U4323QE 9BQR2P3" disable''
      && !(has richDisabledCfg "transform")
      && !(has richDisabledCfg "mode 1920x1080")
      && !(has richDisabledCfg "scale 1.5")
      && !(has richDisabledCfg "position 1920 0");

    # ── CONNECTOR MATCHING NEEDS NO MONITOR TABLE AT ALL ─────────────────────────────────────
    "a connector-matched output renders its bare connector name, unquoted-safe" =
      has connectorOnlyCfg ''output "DP-1"'';

    # ── mode/modeline TRANSLATION ────────────────────────────────────────────────────────────
    # PLAIN `mode`, never `mode --custom`: proven against the real scroll 1.12 binary (see
    # `checks/config-accepted.nix`) that `--custom` names an unlisted/custom MODELINE, not "a mode
    # written by hand" -- `mode 1920x1080@60Hz` and `mode 1920x1080` are both plain, ordinary modes
    # scroll accepts without it.
    "modeline is passed through verbatim, including sync polarity" =
      has
        (render [
          (withLayout
            [ (base // {
                modeline = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
              })
            ]
            { dell = dell; })
        ])
        "modeline 148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";

    "a bare mode gains scroll's required Hz suffix" =
      has
        (render [ (withLayout [ (base // { mode = "1920x1080@60"; }) ] { dell = dell; }) ])
        "mode 1920x1080@60Hz";

    "a mode with no refresh rate is passed through with no Hz appended" =
      has
        (render [ (withLayout [ (base // { mode = "1920x1080"; }) ] { dell = dell; }) ])
        "mode 1920x1080"
      && !(has
        (render [ (withLayout [ (base // { mode = "1920x1080"; }) ] { dell = dell; }) ])
        "Hz");

    "modeline takes precedence over mode when both are somehow set" =
      !(has
        (render [
          (withLayout
            [ (base // {
                mode = "1920x1080@60";
                modeline = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
              })
            ]
            { dell = dell; })
        ])
        "mode 1920x1080@60Hz");

    # ── SCALE AND POSITION ───────────────────────────────────────────────────────────────────
    "scale and position render as scroll's own directives" =
      has
        (render [
          (withLayout
            [ (base // { scale = 1.5; position = { x = 1920; y = 0; }; }) ]
            { dell = dell; })
        ])
        "scale 1.5"
      && has
        (render [
          (withLayout
            [ (base // { scale = 1.5; position = { x = 1920; y = 0; }; }) ]
            { dell = dell; })
        ])
        "position 1920 0";

    # ── NO nixdesktop AT ALL: renders nothing extra, never an error ─────────────────────────
    "with no nixdesktop composed and no layout named, this module still evaluates and renders nothing extra" =
      let cfg = render [ ]; in
      !(has cfg "output \"Dell") && !(has cfg "output \"DP-1\"") && lib.stringLength cfg > 100;

    # A monitor slug the probed table does not contain renders NO stanza, silently — nixdesktop's
    # own modules/layouts.nix already hard-asserts this cannot happen in a properly composed tree;
    # reaching here with a dangling slug can only mean the two tables were composed apart, which
    # is this module's WARNING to raise (proven by the two cases below), not an assertion to
    # duplicate.
    "a monitor slug absent from the monitors table renders no stanza, not a crash" =
      let cfg = render [ (withLayout [ base ] { }) ]; in
      lib.isString cfg && !(has cfg "output \"Dell");

    # ── FACT-WIRING: the warnings this module raises when nixdesktop is only PARTLY composed ──
    #
    # Both checks below filter for THIS module's OWN synthesized message by substring rather than
    # comparing the whole `warnings` list, deliberately: `lib.probeFact`'s "composed" test is
    # `config ? nixdesktop` alone (see home/scroll.nix's own comment on this, verified directly
    # against nixhost's `lib/facts.nix`), so a fixture composing only PART of nixdesktop's option
    # surface (as every fixture in this file necessarily does -- none imports nixdesktop's real
    # modules, see this file's header) can legitimately carry OTHER, unrelated "unresolved"
    # warnings of its own. A whole-list equality here would make this check fail on a property of
    # the shared probing mechanism that has nothing to do with the behaviour under test.
    #
    # This is a DIFFERENT failure than the "SILENT NO-OP" group below: here the TABLE itself moved
    # (`nixdesktop.layouts`/`nixdesktop.sessions` renamed to something else), which is exactly what
    # `probeFact`'s own "unresolved" state exists to catch and is still reported as a `warning` (not
    # an assertion, matching every other probeFact rename-warning in this module); below, the TABLE
    # is reachable but the NAME given does not appear in it, which is this module's own, stricter
    # check.
    "nixdesktop.layouts composed but renamed still warns (the TABLE moved, not the name)" =
      let
        w = (evalScroll [
          { options.nixdesktop.autolayouts = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; }; }
          { config.nixdesktop.autolayouts.desk = { description = "fixture"; outputs = [ ]; }; }
          { config.programs.scroll.nixdesktop.layout = "desk"; }
        ]).warnings;
        ours = lib.filter (m: has m "nixdesktop.layouts") w;
      in
      lib.length ours == 1;

    "nixdesktop.sessions composed but renamed still warns (the TABLE moved, not the name)" =
      let
        w = (evalScroll [
          { options.nixdesktop.autosessions = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; }; }
          { config.nixdesktop.autosessions.primary = { permittedDevices = [ ]; deniedDevices = [ ]; }; }
          { config.programs.scroll.nixdesktop.session = "primary"; }
        ]).warnings;
        ours = lib.filter (m: has m "nixdesktop.sessions") w;
      in
      lib.length ours == 1;

    # ── THE SILENT NO-OP THIS FILE'S HEADER WARNS ABOUT ─────────────────────────────────────
    #
    # Naming a layout or session that does not resolve used to render NOTHING with no warning and
    # no assertion whenever the probed table was EMPTY -- which is exactly the state a host with
    # nixdesktop not composed at all is in. These now fail the build (an `assertions` entry with
    # `assertion = false`), unconditionally on whether the table is empty or populated, because
    # both are "this name does not resolve" from the caller's point of view.
    "naming a layout absent from a declared (non-empty) table fails the build, naming the declared ones" =
      let
        a = (evalScroll [
          { options.nixdesktop.layouts = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; }; }
          { config.nixdesktop.layouts.desk = { description = "fixture"; outputs = [ ]; }; }
          { config.programs.scroll.nixdesktop.layout = "typo-desk"; }
        ]).assertions;
        ours = lib.filter (x: has x.message "programs.scroll.nixdesktop.layout") a;
      in
      lib.length ours == 1 && !(lib.head ours).assertion && has (lib.head ours).message "desk";

    "naming NO layout at all (null, the default) raises no failing assertion of our own" =
      let
        a = (evalScroll [
          { options.nixdesktop.layouts = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; }; }
          { config.nixdesktop.layouts.desk = { description = "fixture"; outputs = [ ]; }; }
        ]).assertions;
      in
      lib.filter (x: has x.message "programs.scroll.nixdesktop.layout") a == [ ];

    # THE CASE THAT USED TO BUILD CLEAN WITH ZERO OUTPUT LINES: nixdesktop not composed AT ALL (no
    # `nixdesktop.layouts` option even declared anywhere -- the real "absent" probeFact state, not
    # merely "empty") and a layout named anyway. Before this fix: `warnings == [ ]`, every
    # assertion true, `xdg.configFile."scroll/config".text` renders no layout-driven `output` line
    # -- a completely wrong config that built without a single diagnostic. Composes NOTHING under
    # `nixdesktop` except the option `programs.scroll.nixdesktop.layout` itself declares.
    "naming a layout with nixdesktop not composed at all fails the build, not silently" =
      let
        a = (evalScroll [ { config.programs.scroll.nixdesktop.layout = "docked"; } ]).assertions;
        ours = lib.filter (x: has x.message "programs.scroll.nixdesktop.layout") a;
      in
      lib.length ours == 1 && !(lib.head ours).assertion;

    "naming a session absent from a declared (non-empty) table fails the build, naming the declared ones" =
      let
        a = (evalScroll [
          { options.nixdesktop.sessions = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; }; }
          { config.nixdesktop.sessions.primary = { permittedDevices = [ ]; deniedDevices = [ ]; }; }
          { config.programs.scroll.nixdesktop.session = "typo-primary"; }
        ]).assertions;
        ours = lib.filter (x: has x.message "programs.scroll.nixdesktop.session") a;
      in
      lib.length ours == 1 && !(lib.head ours).assertion && has (lib.head ours).message "primary";

    "naming NO session at all (null, the default) raises no failing assertion of our own" =
      let
        a = (evalScroll [
          { options.nixdesktop.sessions = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; }; }
          { config.nixdesktop.sessions.primary = { permittedDevices = [ ]; deniedDevices = [ ]; }; }
        ]).assertions;
      in
      lib.filter (x: has x.message "programs.scroll.nixdesktop.session") a == [ ];

    "naming a session with nixdesktop not composed at all fails the build, not silently" =
      let
        a = (evalScroll [ { config.programs.scroll.nixdesktop.session = "primary"; } ]).assertions;
        ours = lib.filter (x: has x.message "programs.scroll.nixdesktop.session") a;
      in
      lib.length ours == 1 && !(lib.head ours).assertion;

    # ── permittedDrmDevices: nixgpu's stable PATHS, never bare device names ─────────────────
    "permittedDrmDevices resolves nixdesktop.sessions.<name>.permittedDevices names to nixgpu's cardPath, in claim order" =
      (evalScroll [
        (withNixgpuDevices nixgpuDevices)
        (withSession [ "amd" "evdi0" ])
      ]).programs.scroll.nixdesktop.permittedDrmDevices == [
        "/dev/dri/by-path/pci-0000:0a:00.0-card"
        "/dev/dri/by-path/platform-evdi.0-card"
      ];

    "no session named (null, the default) leaves permittedDrmDevices empty" =
      (evalScroll [ ]).programs.scroll.nixdesktop.permittedDrmDevices == [ ];

    "a permitted device name absent from nixgpu's inventory is dropped, not thrown" =
      (evalScroll [
        (withNixgpuDevices nixgpuDevices)
        (withSession [ "amd" "ghost" ])
      ]).programs.scroll.nixdesktop.permittedDrmDevices == [ "/dev/dri/by-path/pci-0000:0a:00.0-card" ];

    # THE TRAP-1 CASE: a device the inventory DOES contain but that declares no `address` throws
    # the moment its real `cardPath` is forced (see nixgpu's own option and `nixgpuDevices.noAddress`
    # above) -- a bare `x.cardPath or null` would NOT catch that (the attribute is structurally
    # present; `or` never fires), and the whole build would die on an unrelated host's unrelated
    # device. Proves `drmCardPathOf`'s `builtins.tryEval` actually is doing something, not merely
    # decorative.
    "a permitted device present in the inventory but missing an address is dropped, not a build failure" =
      (evalScroll [
        (withNixgpuDevices nixgpuDevices)
        (withSession [ "noAddress" "amd" ])
      ]).programs.scroll.nixdesktop.permittedDrmDevices == [ "/dev/dri/by-path/pci-0000:0a:00.0-card" ];

    "with a session named but no nixgpu inventory composed at all, every permitted name drops silently rather than crashing" =
      (evalScroll [ (withSession [ "amd" ]) ]).programs.scroll.nixdesktop.permittedDrmDevices == [ ];
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
# `pkgs.emptyFile`, not `pkgs.runCommand "..." {} "touch $out"` — see `checks/startup-contract.nix`
# for the full reasoning: this check decides everything at evaluation time, and a system-dependent
# marker becomes a real foreign-arch build under `nix flake check --all-systems`.
if failed == [ ]
then pkgs.emptyFile
else throw ''
  nixscroll: the nixdesktop layout/monitor/session translation is wrong. Failing assertions:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
''
