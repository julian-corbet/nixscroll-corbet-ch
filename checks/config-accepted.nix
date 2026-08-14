# checks/config-accepted.nix — feed this module's own output to the real scroll binary.
#
# WHY THIS EXISTS. Every other check here evaluates Nix and inspects the result, which can only ever
# prove that the module renders what the module intended. It cannot prove that scroll AGREES, and
# for a config generator that is the only question that matters. The first time this module's output
# was run past the real binary it emitted ten directives scroll rejects outright -- an entire
# `snapping` family that scroll has never had, two `center_*_if_fits` options, and two window
# decoration classes inherited from sway's manual rather than scroll's. All of it type-checked
# perfectly and rendered without complaint.
#
# THE FAILURE MODE THIS CLOSES IS SILENT AT EVERY LAYER:
#
#   * `scroll --validate` prints "Unknown/invalid command 'x'" to stderr and then EXITS 0. A check
#     that gates on the exit code passes a config full of rejected directives. This check therefore
#     greps stderr and ignores the status entirely -- see the grep below, and do not "simplify" it
#     into `scroll -C && ...`, which would silently stop testing anything.
#   * At runtime scroll does the same thing: it logs the bad line and carries on. The session comes
#     up looking fine, minus whatever the rejected directives were supposed to do. This repo's flake
#     used to reason that "a malformed bindsym surfaces the moment scroll starts". It does not.
#
# WHAT IT COVERS. One config exercising a broad spread of the option surface, not a minimal smoke
# test: a bare `enable = true` renders five lines and would have caught none of the ten bugs. When
# adding an option to home/scroll.nix, add it here too -- an option absent from this fixture is an
# option no one has ever asked scroll about.
{ pkgs, scroll, scrollModule }:
let
  lib = pkgs.lib;

  # Minimal stand-in for the home-manager surface the module writes into. Deliberately covers
  # everything the module MAY write, not just what this check reads: a stub narrower than the real
  # surface fails by blaming the module for writing an option the stub forgot to declare.
  hmStub = { lib, ... }: {
    options = {
      xdg.configFile = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; };
      home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; default = [ ]; };
      home.sessionVariables = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      systemd.user.services = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; };
      systemd.user.targets = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.unspecified; default = [ ]; };
      warnings = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    };
  };

  fixture = {
    programs.scroll = {
      enable = true;

      settings = {
        modifier = "Mod4";
        terminal = "foot";
        menu = "fuzzel";
        floatingModifier = "Mod4";
        gaps = { inner = 6; outer = 3; };
        focus = { wrapping = "no"; followsMouse = "yes"; onWindowActivation = "focus"; };
        # Every class in `validColorClasses`, so the assertion's whitelist and scroll's real
        # vocabulary are checked against each other rather than merely against themselves.
        colors = {
          focused = "#4c7899 #285577 #ffffff #2e9ef4 #285577";
          focused_inactive = "#333333 #5f676a #ffffff #484e50 #5f676a";
          focused_tab_title = "#333333 #5f676a #ffffff";
          pinned = "#2f343a #900000 #ffffff #900000 #900000";
          pinned_focused = "#2f343a #900000 #ffffff #900000 #900000";
          selected = "#333333 #5f676a #ffffff #484e50 #5f676a";
          selected_focused = "#4c7899 #285577 #ffffff #2e9ef4 #285577";
          placeholder = "#000000 #0c0c0c #ffffff #000000 #0c0c0c";
          unfocused = "#333333 #222222 #888888 #292d2e #222222";
          urgent = "#2f343a #900000 #ffffff #900000 #900000";
          background = "#ffffff";
        };
      };

      layout = {
        defaultOrientation = "horizontal";
        defaultWidth = 0.5;
        defaultHeight = 1.0;
        widths = [ 0.33 0.5 0.67 1.0 ];
        heights = [ 0.5 1.0 ];
        cycleSizeWrap = true;
        alignResetAuto = true;
        maximizeIfSingle = true;
      };

      animations = { enable = true; style = "scale"; };
      jump.labelKeys = "asdfghjkl";
      bar = {
        position = "top";
        statusCommand = "while date +'%Y-%m-%d %X'; do sleep 1; done";
        scrollerIndicator = true;
        trailsIndicator = true;
      };
      outputs."VGA-1" = {
        resolution = "1920x1080@60Hz";
        position = "0 0";
        background = "#1a1b26 solid_color";
        scale = 1.0;
        layout.type = "horizontal";
      };
      startup = [ "mako" "waybar" ];
      xwayland = "enable";

      # Exercises the nixdesktop-layout translation (home/scroll.nix's `renderLayoutOutput`)
      # through the SAME real-binary gate as every hand-written option above -- see
      # `nixdesktopFixture` below for the table this names.
      nixdesktop.layout = "desk";

      # Exercises the nixdesktop.sessions.<name>.virtualOutputs -> create_output/output-mode
      # translation (home/scroll.nix's `virtualOutputLines`) through the SAME real-binary gate --
      # see `nixdesktopFixture` below for the session this names. `checks/virtual-outputs.nix`
      # already proves this module renders what it INTENDS (the exact HEADLESS-<N+1> text); this
      # is the one check that asks scroll's own parser whether the generated `exec` LINE ITSELF
      # is valid config syntax -- the `exec` directive's payload is opaque to `--validate` (it
      # never runs the shell command), so what this actually proves is that our quoting of the
      # whole line does not break the CONFIG file's own tokenizer, which would otherwise silently
      # swallow or truncate whatever comes after it.
      nixdesktop.session = "primary";
    };
  };

  # A `nixdisplay.layouts`/`nixdisplay.monitors` stand-in -- minimal on purpose (see
  # `checks/layout-outputs.nix`'s own header for why this repo does not import nixdisplay's real
  # modules here either). Exercises every directive `renderLayoutOutput` can emit in one pass: a
  # raw modeline (the ast2500 sync-polarity case the option exists for), an identity matcher with
  # embedded spaces (quoting), an inverted transform (90 -> 270 on the wire), scale, position, a
  # plain `mode` translation from a bare "WIDTHxHEIGHT@RATE" with no Hz suffix (normalised to add
  # one -- NOT `mode --custom`, which names an unlisted/custom MODELINE and was never the right
  # directive here, see home/scroll.nix's own `normaliseModeRate` comment), a bare mode with no
  # refresh rate at all passed through unchanged, and a disabled connector-matched output emitting
  # only `disable`.
  nixdesktopFixture = { lib, ... }: {
    options.nixdisplay = {
      layouts = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
      monitors = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    };
    options.nixdesktop = {
      sessions = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    };
    config.nixdisplay = {
      monitors.la2306 = {
        make = "HP Inc.";
        model = "HP LA2306";
        serial = "3CQ1234567";
        identifier = "HP Inc. HP LA2306 3CQ1234567";
        aliases = [ ];
      };
      layouts.desk = {
        description = "fixture";
        outputs = [
          {
            monitor = "la2306";
            connector = null;
            match = "identity";
            enable = true;
            mode = null;
            modeline = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
            scale = 1.0;
            position = { x = 0; y = 0; };
            transform = "90";
          }
          {
            # Enabled, on purpose: a disabled output renders ONLY `disable` (see home/scroll.nix's
            # own `renderLayoutOutput`), so a `mode` value here would never reach scroll's parser
            # at all if this entry were disabled -- exercising the Hz-suffix normalisation through
            # the real binary needs an output that actually renders it.
            monitor = null;
            connector = "HDMI-A-2";
            match = "connector";
            enable = true;
            mode = "1920x1080@60";
            modeline = null;
            scale = null;
            position = null;
            transform = "normal";
          }
          {
            # A bare mode with NO refresh rate at all -- `normaliseModeRate` must pass this
            # through completely unchanged, appending no `Hz` where there was no rate to begin
            # with.
            monitor = null;
            connector = "DP-2";
            match = "connector";
            enable = true;
            mode = "1920x1080";
            modeline = null;
            scale = null;
            position = null;
            transform = "normal";
          }
          {
            # Disabled: proves `output "DP-3" disable` alone is a config the real binary accepts,
            # with none of this entry's other (deliberately non-null) fields reaching it.
            monitor = null;
            connector = "DP-3";
            match = "connector";
            enable = false;
            mode = "1920x1080@60";
            modeline = null;
            scale = 2.0;
            position = { x = 0; y = 1440; };
            transform = "180";
          }
        ];
      };
    };
    config.nixdesktop = {
      # Exercises the virtualOutputs -> create_output/output-mode translation (home/scroll.nix's
      # `virtualOutputLines`) through the real binary: two entries, so this also proves the
      # SECOND exec line's HEADLESS-3 addressing (not just the FALLBACK-offset HEADLESS-2 of the
      # first) parses cleanly, not merely the single-output case.
      sessions.primary = {
        permittedDevices = [ ];
        deniedDevices = [ ];
        virtualOutputs = [
          { width = 1920; height = 1080; }
          { width = 2560; height = 1440; }
        ];
      };
    };
  };

  # A config that MUST be rejected. This is the check's own self-test -- see the runCommand.
  poison = pkgs.writeText "scroll-poison.config" ''
    bogus_directive_that_scroll_cannot_know true
  '';

  # `scrollModule` arrives ALREADY partially applied (flake.nix closes `home/scroll.nix` over the
  # real, locked `nixhost.lib.probeFact` before this check ever runs) -- see
  # checks/startup-contract.nix's own header for why this file never reaches for the raw
  # `../home/scroll.nix` path itself either.
  rendered = (lib.evalModules {
    modules = [ scrollModule hmStub nixdesktopFixture { _module.args.pkgs = pkgs; } fixture ];
  }).config.xdg.configFile."scroll/config".text;

  configFile = pkgs.writeText "scroll-fixture.config" rendered;
in
pkgs.runCommand "scroll-config-accepted"
{
  # dbus is not decoration: the `scroll` on PATH is a wrapper that execs `dbus-run-session`, so
  # without dbus-daemon it dies with "failed to execute message bus daemon" before parsing anything.
  # That was the SECOND way this check found to look green while testing nothing.
  nativeBuildInputs = [ scroll pkgs.dbus ];
  inherit configFile poison;
} ''
  # scroll ABORTS before it ever opens the config unless XDG_RUNTIME_DIR is set, and a build
  # sandbox has no such variable. It exits printing one line -- "XDG_RUNTIME_DIR is not set in the
  # environment. Aborting." -- which contains none of the strings this check greps for, so without
  # these two lines the check passed a config containing a deliberately bogus directive and
  # reported "every generated directive was accepted". Verified, not theorised.
  export XDG_RUNTIME_DIR="$PWD/xdg"; mkdir -p "$XDG_RUNTIME_DIR"
  export WLR_BACKENDS=headless

  # scroll's wrapper otherwise execs `dbus-run-session`, which cannot start in a sandbox (no
  # /etc/dbus-1/session.conf) and takes scroll down with it before it reads the config -- the THIRD
  # early-abort this check hit. The wrapper's own first branch skips dbus entirely when this is
  # set, handing straight off to the real binary. Validation never talks to the bus, so a bus that
  # does not exist is the honest thing to declare here.
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/dev/null"

  # Neither invocation below tests scroll's exit status, on purpose: `--validate` returns 0 even
  # when it has rejected every directive in the file, so stderr is the ONLY signal there is. Do not
  # "simplify" these into `scroll -C && ...`; that stops testing anything.
  errs() { grep -cE "Error on line|Unknown/invalid" "$1" || true; }

  # ── SELF-TEST FIRST ────────────────────────────────────────────────────────────────────────────
  # Prove the validator actually parses configs in THIS environment before believing anything it
  # says about ours. A green result from a validator that never ran is precisely the failure this
  # check exists to catch, and the check is not entitled to exempt itself from it. If a future
  # scroll grows another early-abort path, this fails loudly instead of going quietly green.
  scroll --validate --config "$poison" > poison.log 2>&1 || true
  if [ "$(errs poison.log)" -eq 0 ]; then
    echo "FAIL: the self-test config was NOT rejected, so scroll never parsed it here."
    echo "This check cannot report anything about the real config until that is fixed."
    echo "--- what scroll said about the poison config ---"
    cat poison.log
    exit 1
  fi
  echo "self-test OK: scroll rejects a known-bad directive in this environment."

  # ── THE ACTUAL CHECK ───────────────────────────────────────────────────────────────────────────
  echo "== validating the rendered config against $(scroll --version) =="
  cat "$configFile"
  scroll --validate --config "$configFile" > out.log 2>&1 || true

  # EGL/DRM/vulkan complaints are expected with no seat and no GPU and say nothing about the config.
  if grep -E "Error on line|Unknown/invalid" out.log; then
    echo
    echo "FAIL: scroll rejected directives that programs.scroll generated."
    echo "Each line above names the directive and the line it was emitted on. Either the option"
    echo "should not exist (scroll has no such feature -- check all five of ITS man pages, not"
    echo "sway's), or it renders the wrong spelling."
    exit 1
  fi

  echo "OK: every generated directive was accepted."
  touch $out
''
