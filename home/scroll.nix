# home/scroll.nix — homeManagerModules.scroll: generates ~/.config/scroll/config from
# structured options (namespace: programs.scroll), matching scroll's own upstream config
# syntax (see `man 5 scroll`, `man 5 scroll-input`, `man 5 scroll-output`, `man 5 scroll-bar`).
#
# Installs nothing. This module never touches home.packages — see README for why (mechanism
# vs platform-backend split, same doctrine as nixdesktop/nixremote). The one place a `package`
# is even accepted (below) is used only to resolve an absolute binary path *inside the
# generated config text*, never to put anything on $PATH.
#
# NOT AN OPTION PER MODE NAME. scroll's own default config defines named i3/sway modal
# keymaps — mode "wssplit" { ... }, mode "jump" { ... }, mode "filter" { ... }, and so on for
# modifiers/setsizeh/setsizev/resize/floating/togglesizeh/togglesizev/align/fit_size/
# trailmark/trail/spaces. These are NOT scroll mechanisms; they're ordinary sway mode blocks
# scroll inherited by being a sway fork, and scroll ships working defaults for every one of
# them already (see scroll's own /etc/scroll/config, installed by the package). Modeling one
# option per mode name here would be modeling sway's modal-keymap feature, not scroll. Real
# scroll config directives — the ones that don't exist in plain sway — get real options below
# (layout_*, animations, jump_labels_*, gesture_scroll_*, snap_*, scale_workspace/scale_content
# via bar, ...); keymaps of any kind, including overriding scroll's own named modes, go through
# the generic `binds`/`modes` escape hatch.
{ lib, config, ... }:
let
  cfg = config.programs.scroll;

  inherit (lib) mkEnableOption mkOption types mkIf mkMerge mkDefault optional optionals optionalString concatStringsSep concatMapStringsSep filter;

  num = types.either types.int types.float;
  tf = b: if b then "true" else "false"; # scroll's own <true|false> directives
  yn = b: if b then "yes" else "no"; # animations/bar's own <yes|no> directives

  # One shared shape for every animations channel (`default`, `windowOpen`, ...). `enable`
  # defaults to true because setting the submodule at all (even `{}`) means "yes, animate this,
  # using scroll's own duration/curve unless I say otherwise" — `null` at the parent option
  # (the default for every channel) is the "leave scroll's own default alone, don't emit
  # anything" case, handled by renderCurve below returning null for it.
  animCurveType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enabled state for this animation channel (`enabled yes|no`).";
      };
      duration = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
        description = "Duration in milliseconds. Omitted from the generated line if null.";
      };
      curve = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "var 3 [ 0.215 0.61 0.355 1 ]";
        description = ''
          Everything scroll's `animations` grammar accepts after the duration, written
          exactly as it appears in the config file — a `var <order> [ <control points> ]`
          clause, optionally followed by an `off <scale> <order> [ <control points> ]`
          clause. Raw on purpose: scroll's Bezier-curve grammar (arbitrary order, an
          optional second curve for the non-moving axis) has no natural finite option
          tree — see `man 5 scroll`'s `animations` section for the full format. Omitted
          from the generated line if null, which uses scroll's own curve for this channel.
        '';
      };
    };
  };

  renderCurve = c:
    if c == null then null
    else
      concatStringsSep " " ([ (yn c.enable) ]
        ++ optional (c.enable && c.duration != null) (toString c.duration)
        ++ optional (c.enable && c.curve != null) c.curve);

  animDirective = name: c:
    let r = renderCurve c; in
    if r == null then null else "${name} ${r}";

  # ── settings ──────────────────────────────────────────────────────────────────────────
  settingsLines = filter (x: x != null) [
    (optionalIf (cfg.settings.modifier != null) "set $mod ${cfg.settings.modifier}")
    (optionalIf (cfg.settings.terminal != null) "set $term ${cfg.settings.terminal}")
    (optionalIf (cfg.settings.menu != null) "set $menu ${cfg.settings.menu}")
    (optionalIf (cfg.settings.gaps.inner != null) "gaps inner ${toString cfg.settings.gaps.inner}")
    (optionalIf (cfg.settings.gaps.outer != null) "gaps outer ${toString cfg.settings.gaps.outer}")
    (optionalIf (cfg.settings.floatingModifier != null) "floating_modifier ${cfg.settings.floatingModifier}")
    (optionalIf (cfg.settings.focus.wrapping != null) "focus_wrapping ${cfg.settings.focus.wrapping}")
    (optionalIf (cfg.settings.focus.followsMouse != null) "focus_follows_mouse ${cfg.settings.focus.followsMouse}")
    (optionalIf (cfg.settings.focus.onWindowActivation != null) "focus_on_window_activation ${cfg.settings.focus.onWindowActivation}")
  ] ++ (map (name: "client.${name} ${cfg.settings.colors.${name}}") (lib.attrNames cfg.settings.colors));

  # ── layout ────────────────────────────────────────────────────────────────────────────
  defaultModeParts = filter (x: x != null) [
    cfg.layout.defaultMode.position
    cfg.layout.defaultMode.focus
    (if cfg.layout.defaultMode.reorderAuto == null then null else if cfg.layout.defaultMode.reorderAuto then "reorder_auto" else "noreorder_auto")
    (if cfg.layout.defaultMode.centerHorizontal == null then null else if cfg.layout.defaultMode.centerHorizontal then "center_horiz" else "nocenter_horiz")
    (if cfg.layout.defaultMode.centerVertical == null then null else if cfg.layout.defaultMode.centerVertical then "center_vert" else "nocenter_vert")
  ];

  layoutLines = filter (x: x != null) [
    (optionalIf (cfg.layout.defaultOrientation != null) "default_orientation ${cfg.layout.defaultOrientation}")
    (optionalIf (cfg.layout.defaultWidth != null) "layout_default_width ${toString cfg.layout.defaultWidth}")
    (optionalIf (cfg.layout.defaultHeight != null) "layout_default_height ${toString cfg.layout.defaultHeight}")
    (optionalIf (cfg.layout.widths != null) "layout_widths [${concatStringsSep " " (map toString cfg.layout.widths)}]")
    (optionalIf (cfg.layout.heights != null) "layout_heights [${concatStringsSep " " (map toString cfg.layout.heights)}]")
    (optionalIf (defaultModeParts != [ ]) "layout_default_mode ${concatStringsSep " " defaultModeParts}")
    (optionalIf (cfg.layout.cycleSizeWrap != null) "cycle_size_wrap ${tf cfg.layout.cycleSizeWrap}")
    (optionalIf (cfg.layout.alignResetAuto != null) "align_reset_auto ${tf cfg.layout.alignResetAuto}")
    (optionalIf (cfg.layout.maximizeIfSingle != null) "maximize_if_single ${tf cfg.layout.maximizeIfSingle}")
    (optionalIf (cfg.layout.centerHorizontalIfFits != null) "center_horizontal_if_fits ${tf cfg.layout.centerHorizontalIfFits}")
    (optionalIf (cfg.layout.centerVerticalIfFits != null) "center_vertical_if_fits ${tf cfg.layout.centerVerticalIfFits}")
  ];

  # ── animations ────────────────────────────────────────────────────────────────────────
  animationsInner = filter (x: x != null) ([
    (optionalIf (cfg.animations.enable != null) "enabled ${yn cfg.animations.enable}")
    (optionalIf (cfg.animations.style != null) "style ${cfg.animations.style}")
  ] ++ [
    (animDirective "default" cfg.animations.default)
    (animDirective "window_open" cfg.animations.windowOpen)
    (animDirective "window_move" cfg.animations.windowMove)
    (animDirective "window_size" cfg.animations.windowSize)
    (animDirective "workspace_switch" cfg.animations.workspaceSwitch)
    (animDirective "jump" cfg.animations.jump)
    (animDirective "overview" cfg.animations.overview)
    (animDirective "fade_in" cfg.animations.fadeIn)
    (animDirective "fade_out" cfg.animations.fadeOut)
  ]);

  animationsBlock =
    if animationsInner == [ ] then null
    else concatStringsSep "\n" ([ "animations {" ] ++ (map (l: "    ${l}") animationsInner) ++ [ "}" ]);

  # ── decoration ────────────────────────────────────────────────────────────────────────
  decorationParts = filter (x: x != null) [
    (optionalIf (cfg.decoration.borderRadius != null) "border_radius ${toString cfg.decoration.borderRadius}")
    (optionalIf (cfg.decoration.shadow.enable != null) "shadow ${tf cfg.decoration.shadow.enable}")
    (optionalIf (cfg.decoration.shadow.dynamic != null) "shadow_dynamic ${tf cfg.decoration.shadow.dynamic}")
    (optionalIf (cfg.decoration.shadow.size != null) "shadow_size ${toString cfg.decoration.shadow.size}")
    (optionalIf (cfg.decoration.shadow.blur != null) "shadow_blur ${toString cfg.decoration.shadow.blur}")
    (optionalIf (cfg.decoration.shadow.offset != null) "shadow_offset ${toString (builtins.elemAt cfg.decoration.shadow.offset 0)} ${toString (builtins.elemAt cfg.decoration.shadow.offset 1)}")
    (optionalIf (cfg.decoration.shadow.color != null) "shadow_color ${cfg.decoration.shadow.color}")
    (optionalIf (cfg.decoration.dim.enable != null) "dim ${tf cfg.decoration.dim.enable}")
    (optionalIf (cfg.decoration.dim.color != null) "dim_color ${cfg.decoration.dim.color}")
  ];

  decorationLine = optionalIf (decorationParts != [ ]) "default_decoration ${concatStringsSep " " decorationParts}";

  # ── jump ──────────────────────────────────────────────────────────────────────────────
  jumpLines = filter (x: x != null) [
    (optionalIf (cfg.jump.labelKeys != null) "jump_labels_keys ${cfg.jump.labelKeys}")
    (optionalIf (cfg.jump.labelColor != null) "jump_labels_color ${cfg.jump.labelColor}")
    (optionalIf (cfg.jump.labelBackground != null) "jump_labels_background ${cfg.jump.labelBackground}")
    (optionalIf (cfg.jump.labelScale != null) "jump_labels_scale ${toString cfg.jump.labelScale}")
    (optionalIf (cfg.jump.labelSwallow != null) "jump_labels_swallow ${tf cfg.jump.labelSwallow}")
  ];

  # ── gestures ──────────────────────────────────────────────────────────────────────────
  gestureLines = filter (x: x != null) [
    (optionalIf (cfg.gestures.scroll.enable != null) "gesture_scroll_enable ${tf cfg.gestures.scroll.enable}")
    (optionalIf (cfg.gestures.scroll.fingers != null) "gesture_scroll_fingers ${toString cfg.gestures.scroll.fingers}")
    (optionalIf (cfg.gestures.scroll.sensitivity != null) "gesture_scroll_sensitivity ${toString cfg.gestures.scroll.sensitivity}")
    (optionalIf (cfg.gestures.scroll.sensitivityMouse != null) "gesture_scroll_sensitivity_mouse ${toString cfg.gestures.scroll.sensitivityMouse}")
  ];

  # ── snapping ──────────────────────────────────────────────────────────────────────────
  snappingLines = filter (x: x != null) [
    (optionalIf (cfg.snapping.windowGap != null) "snap_window_gap ${toString cfg.snapping.windowGap}")
    (optionalIf (cfg.snapping.workspaceGap != null) "snap_workspace_gap ${toString cfg.snapping.workspaceGap}")
    (optionalIf (cfg.snapping.respectGapsInner != null) "snap_respect_gaps_inner ${tf cfg.snapping.respectGapsInner}")
    (optionalIf (cfg.snapping.respectGapsOuter != null) "snap_respect_gaps_outer ${tf cfg.snapping.respectGapsOuter}")
    (optionalIf (cfg.snapping.borderOverlap != null) "snap_border_overlap ${tf cfg.snapping.borderOverlap}")
  ];

  # ── xwayland ──────────────────────────────────────────────────────────────────────────
  xwaylandLine = optionalIf (cfg.xwayland != null) "xwayland ${cfg.xwayland}";

  # ── outputs ───────────────────────────────────────────────────────────────────────────
  renderOutput = name: o:
    let
      lines = filter (x: x != null) [
        (optionalIf (o.resolution != null) "output ${name} resolution ${o.resolution}")
        (optionalIf (o.position != null) "output ${name} position ${o.position}")
        (optionalIf (o.background != null) "output ${name} background ${o.background}")
        (optionalIf (o.scale != null) "output ${name} scale ${toString o.scale}")
        (optionalIf (o.layout.type != null) "output ${name} layout_type ${o.layout.type}")
        (optionalIf (o.layout.defaultWidth != null) "output ${name} layout_default_width ${toString o.layout.defaultWidth}")
        (optionalIf (o.layout.defaultHeight != null) "output ${name} layout_default_height ${toString o.layout.defaultHeight}")
      ];
    in
    lines;
  outputLines = lib.concatLists (map (name: renderOutput name cfg.outputs.${name}) (lib.attrNames cfg.outputs));

  # ── input ─────────────────────────────────────────────────────────────────────────────
  renderInput = name: settings:
    let keys = lib.attrNames settings; in
    if keys == [ ] then [ ]
    else [ "input \"${name}\" {" ] ++ (map (k: "    ${k} ${settings.${k}}") keys) ++ [ "}" ];
  inputLines = lib.concatLists (map (name: renderInput name cfg.input.${name}) (lib.attrNames cfg.input));

  # ── bar ───────────────────────────────────────────────────────────────────────────────
  barColorLines = map (k: "        ${k} ${cfg.bar.colors.${k}}") (lib.attrNames cfg.bar.colors);
  barColorsBlock = optionals (barColorLines != [ ]) ([ "    colors {" ] ++ barColorLines ++ [ "    }" ]);
  barInner = filter (x: x != null) [
    (optionalIf (cfg.bar.position != null) "    position ${cfg.bar.position}")
    (optionalIf (cfg.bar.statusCommand != null) "    status_command ${cfg.bar.statusCommand}")
    (optionalIf (cfg.bar.scrollerIndicator != null) "    scroller_indicator ${yn cfg.bar.scrollerIndicator}")
    (optionalIf (cfg.bar.trailsIndicator != null) "    trails_indicator ${yn cfg.bar.trailsIndicator}")
  ] ++ barColorsBlock;
  barBlock = optionalIf cfg.bar.enable (concatStringsSep "\n" ([ "bar {" ] ++ barInner ++ [ "}" ]));

  # ── binds / modes ─────────────────────────────────────────────────────────────────────
  bindLines = map
    (k: if cfg.binds.${k} == null then "unbindsym ${k}" else "bindsym ${k} ${cfg.binds.${k}}")
    (lib.attrNames cfg.binds);

  renderMode = name: keys:
    let
      bound = lib.filterAttrs (_: v: v != null) keys;
      names = lib.attrNames bound;
    in
    if names == [ ] then [ ]
    else [ "mode \"${name}\" {" ] ++ (map (k: "    bindsym ${k} ${bound.${k}}") names) ++ [ "}" ];
  modeLines = lib.concatLists (map (name: renderMode name cfg.modes.${name}) (lib.attrNames cfg.modes));

  # ── startup ───────────────────────────────────────────────────────────────────────────
  scrollmsgBin = if cfg.package != null then "${cfg.package}/bin/scrollmsg" else "scrollmsg";
  systemdStartupLines = optionals cfg.systemd.enable [
    "exec dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY I3SOCK SWAYSOCK SCROLLSOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE"
    "exec \"systemctl --user import-environment {,WAYLAND_}DISPLAY I3SOCK SWAYSOCK SCROLLSOCK; systemctl --user start scroll-session.target\""
    "exec ${scrollmsgBin} -t subscribe '[\"shutdown\"]' && systemctl --user stop scroll-session.target"
  ];
  startupLines = systemdStartupLines ++ (map (c: "exec ${c}") cfg.startup);

  optionalIf = cond: v: if cond then v else null;

  sections = filter (s: s != null && s != "") [
    (optionalIf (settingsLines != [ ]) (concatStringsSep "\n" settingsLines))
    (optionalIf (layoutLines != [ ]) (concatStringsSep "\n" layoutLines))
    animationsBlock
    decorationLine
    (optionalIf (jumpLines != [ ]) (concatStringsSep "\n" jumpLines))
    (optionalIf (gestureLines != [ ]) (concatStringsSep "\n" gestureLines))
    (optionalIf (snappingLines != [ ]) (concatStringsSep "\n" snappingLines))
    xwaylandLine
    (optionalIf (outputLines != [ ]) (concatStringsSep "\n" outputLines))
    (optionalIf (inputLines != [ ]) (concatStringsSep "\n" inputLines))
    barBlock
    (optionalIf (bindLines != [ ]) (concatStringsSep "\n" bindLines))
    (optionalIf (modeLines != [ ]) (concatStringsSep "\n" modeLines))
    (optionalIf (startupLines != [ ]) (concatStringsSep "\n" startupLines))
    (optionalIf (cfg.extraConfig != "") cfg.extraConfig)
  ];

  renderedConfig = ''
    # Generated by nixscroll (programs.scroll). Do not edit by hand — changes are overwritten
    # on the next `home-manager switch`. See `man 5 scroll` for what each directive below does.
  '' + concatStringsSep "\n\n" sections + "\n";
in
{
  options.programs.scroll = {
    enable = mkEnableOption "generating ~/.config/scroll/config for scroll (a scrolling/PaperWM-style fork of sway)";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = lib.literalExpression "inputs.nixscroll.packages.\${system}.scroll";
      description = ''
        Used ONLY to resolve one absolute binary path this module writes into the generated
        config — the `scrollmsg` call in the `systemd.enable` session-teardown line below.
        Never added to `home.packages`; this module installs nothing (see README). `null`,
        the default, writes bare `scrollmsg` instead, resolved through `$PATH` at runtime by
        whatever actually installed scroll (a platform backend, `nixosModules.scroll`, or a
        distro package).
      '';
    };

    xwayland = mkOption {
      type = types.nullOr (types.enum [ "enable" "disable" "force" ]);
      default = null;
      description = ''
        `xwayland enable|disable|force`. `null` (the default) omits the directive, which
        leaves scroll's own default (XWayland support enabled when the binary was built
        with it) in effect.
      '';
    };

    systemd.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Wires scroll into a `scroll-session.target` systemd user target, the same idiom
        nixpkgs' own sway/scroll NixOS modules use for their `/etc/scroll/config.d/nixos.conf`
        include: imports `DISPLAY`/`WAYLAND_DISPLAY`/socket variables into the D-Bus and
        systemd user environments on startup (needed for screen sharing, Pinentry, and any
        systemd user service that wants them) and stops the target on scroll's shutdown
        event. Also declares the `scroll-session.target` unit itself via home-manager's
        `systemd.user.targets`, so other home-manager-managed services can order themselves
        `After = [ "scroll-session.target" ]` instead of guessing when scroll is ready.
        Set to `false` if your session already handles environment import another way (a
        display manager doing it for you, for instance) and you don't want a target unit
        that nothing binds to.
      '';
    };

    settings = {
      modifier = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "Mod4";
        description = "`set $mod <value>`. The logo/modifier key used throughout scroll's own default bindings.";
      };
      terminal = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "kitty";
        description = "`set $term <value>`.";
      };
      menu = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "wmenu-run";
        description = "`set $menu <value>`.";
      };
      gaps = {
        inner = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "`gaps inner <amount>` — pixels of spacing around each window.";
        };
        outer = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "`gaps outer <amount>` — pixels of spacing around each workspace, in addition to inner gaps.";
        };
      };
      colors = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = { focused = "#15439e #4b4b4b #e0e0e0 #2e9ef4 #15439e"; };
        description = ''
          `client.<name> <border> <background> <text> [<indicator> [<child_border>]]` lines,
          one per attribute. Keys are scroll/sway's window-decoration classes — `focused`,
          `focused_inactive`, `focused_tab_title`, `pinned`, `pinned_focused`, `selected`,
          `selected_focused`, `sticky`, `sticky_focused`, `placeholder`, `unfocused`,
          `urgent`, or the single-argument `background`. See `man 5 scroll`'s CLIENT COLORS
          section for the full list and meaning of each color slot.
        '';
      };
      floatingModifier = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "Mod4 normal";
        description = "`floating_modifier <modifier> [normal|inverse]`.";
      };
      focus = {
        wrapping = mkOption {
          type = types.nullOr (types.enum [ "yes" "no" "force" "workspace" "stay" ]);
          default = null;
          description = "`focus_wrapping yes|no|force|workspace|stay`. Default (scroll's, when unset here) is `no`.";
        };
        followsMouse = mkOption {
          type = types.nullOr (types.enum [ "yes" "no" "always" "full" ]);
          default = null;
          description = "`focus_follows_mouse yes|no|always|full`. Default (scroll's, when unset here) is `yes`.";
        };
        onWindowActivation = mkOption {
          type = types.nullOr (types.enum [ "smart" "urgent" "focus" "none" ]);
          default = null;
          description = "`focus_on_window_activation smart|urgent|focus|none`. Default (scroll's, when unset here) is `focus`.";
        };
      };
    };

    layout = {
      defaultOrientation = mkOption {
        type = types.nullOr (types.enum [ "horizontal" "vertical" "auto" ]);
        default = null;
        description = "`default_orientation horizontal|vertical|auto` — the default container layout for new tiled containers.";
      };
      defaultWidth = mkOption {
        type = types.nullOr num;
        default = null;
        example = 0.5;
        description = "`layout_default_width <fraction>`.";
      };
      defaultHeight = mkOption {
        type = types.nullOr num;
        default = null;
        example = 1.0;
        description = "`layout_default_height <fraction>`.";
      };
      widths = mkOption {
        type = types.nullOr (types.listOf num);
        default = null;
        example = [ 0.33333333 0.5 0.66666667 1.0 ];
        description = "`layout_widths [<fractions...>]` — the cycle_size stops for column/window width.";
      };
      heights = mkOption {
        type = types.nullOr (types.listOf num);
        default = null;
        example = [ 0.33333333 0.5 0.66666667 1.0 ];
        description = "`layout_heights [<fractions...>]` — the cycle_size stops for row/window height.";
      };
      defaultMode = {
        position = mkOption {
          type = types.nullOr (types.enum [ "after" "before" "end" "beg" ]);
          default = null;
          description = "Where new windows are inserted relative to the current one. Part of `layout_default_mode`.";
        };
        focus = mkOption {
          type = types.nullOr (types.enum [ "focus" "nofocus" ]);
          default = null;
          description = "Whether a newly created window takes focus. Part of `layout_default_mode`.";
        };
        reorderAuto = mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "`reorder_auto`/`noreorder_auto`. Part of `layout_default_mode`.";
        };
        centerHorizontal = mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "`center_horiz`/`nocenter_horiz`. Part of `layout_default_mode`.";
        };
        centerVertical = mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "`center_vert`/`nocenter_vert`. Part of `layout_default_mode`.";
        };
      };
      cycleSizeWrap = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "`cycle_size_wrap`. Default (scroll's, when unset here) is `false`.";
      };
      alignResetAuto = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "`align_reset_auto`. Default (scroll's, when unset here) is `true`.";
      };
      maximizeIfSingle = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "`maximize_if_single`. Default (scroll's, when unset here) is `false`.";
      };
      centerHorizontalIfFits = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "`center_horizontal_if_fits`. Default (scroll's, when unset here) is `true`.";
      };
      centerVerticalIfFits = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "`center_vertical_if_fits`. Default (scroll's, when unset here) is `true`.";
      };
    };

    animations = {
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "`animations { enabled yes|no ... }`. Global animations on/off. See also `softwareRendering.enable`.";
      };
      style = mkOption {
        type = types.nullOr (types.enum [ "clip" "scale" ]);
        default = null;
        description = "`animations { style clip|scale ... }`. Default (scroll's, when unset here) is `scale`.";
      };
      default = mkOption {
        type = types.nullOr animCurveType;
        default = null;
        description = "The `default` animation curve — used by every channel below that is left null.";
      };
      windowOpen = mkOption { type = types.nullOr animCurveType; default = null; description = "Curve for windows opening."; };
      windowMove = mkOption { type = types.nullOr animCurveType; default = null; description = "Curve for the `move` command."; };
      windowSize = mkOption { type = types.nullOr animCurveType; default = null; description = "Curve for cycle_size/set_size/fit_size/toggle_size/resize."; };
      workspaceSwitch = mkOption { type = types.nullOr animCurveType; default = null; description = "Curve for workspace switching."; };
      jump = mkOption { type = types.nullOr animCurveType; default = null; description = "Curve for entering/leaving jump mode."; };
      overview = mkOption { type = types.nullOr animCurveType; default = null; description = "Curve for entering/leaving overview mode."; };
      fadeIn = mkOption { type = types.nullOr animCurveType; default = null; description = "Opacity curve for a new window while windowOpen is animating."; };
      fadeOut = mkOption { type = types.nullOr animCurveType; default = null; description = "Opacity curve for a closing window."; };
    };

    decoration = {
      borderRadius = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "`default_decoration border_radius <n>` — GPU-bound. See `softwareRendering.enable`.";
      };
      shadow = {
        enable = mkOption { type = types.nullOr types.bool; default = null; description = "`default_decoration shadow true|false` — GPU-bound. See `softwareRendering.enable`."; };
        dynamic = mkOption { type = types.nullOr types.bool; default = null; description = "`default_decoration shadow_dynamic true|false`."; };
        size = mkOption { type = types.nullOr types.int; default = null; description = "`default_decoration shadow_size <n>`."; };
        blur = mkOption { type = types.nullOr types.int; default = null; description = "`default_decoration shadow_blur <n>`."; };
        offset = mkOption {
          type = types.nullOr (types.listOf types.int);
          default = null;
          example = [ 40 40 ];
          description = "`default_decoration shadow_offset <x> <y>` — a 2-element `[ x y ]` list.";
        };
        color = mkOption { type = types.nullOr types.str; default = null; example = "#00000070"; description = "`default_decoration shadow_color <#RRGGBBAA>`."; };
      };
      dim = {
        enable = mkOption { type = types.nullOr types.bool; default = null; description = "`default_decoration dim true|false` — GPU-bound. See `softwareRendering.enable`."; };
        color = mkOption { type = types.nullOr types.str; default = null; example = "#00000040"; description = "`default_decoration dim_color <#RRGGBBAA>`."; };
      };
    };

    jump = {
      labelKeys = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "1234 [ ampersand eacute quotedbl apostrophe ]";
        description = "`jump_labels_keys <string> [<array of strings>]`, written raw exactly as the directive expects.";
      };
      labelColor = mkOption { type = types.nullOr types.str; default = null; description = "`jump_labels_color <color>`."; };
      labelBackground = mkOption { type = types.nullOr types.str; default = null; description = "`jump_labels_background <color>`."; };
      labelScale = mkOption { type = types.nullOr num; default = null; description = "`jump_labels_scale <number>`."; };
      labelSwallow = mkOption { type = types.nullOr types.bool; default = null; description = "`jump_labels_swallow true|false`."; };
    };

    gestures.scroll = {
      enable = mkOption { type = types.nullOr types.bool; default = null; description = "`gesture_scroll_enable true|false` — trackpad layout-scrolling gesture."; };
      fingers = mkOption { type = types.nullOr types.int; default = null; description = "`gesture_scroll_fingers <number>`."; };
      sensitivity = mkOption { type = types.nullOr num; default = null; description = "`gesture_scroll_sensitivity <number>` — touchpad. Negative reverses direction."; };
      sensitivityMouse = mkOption { type = types.nullOr num; default = null; description = "`gesture_scroll_sensitivity_mouse <number>`. Negative reverses direction."; };
    };

    snapping = {
      windowGap = mkOption { type = types.nullOr types.int; default = null; description = "`snap_window_gap <integer>` — floating-window drag-snap distance in pixels. 0 disables."; };
      workspaceGap = mkOption { type = types.nullOr types.int; default = null; description = "`snap_workspace_gap <integer>`."; };
      respectGapsInner = mkOption { type = types.nullOr types.bool; default = null; description = "`snap_respect_gaps_inner true|false`."; };
      respectGapsOuter = mkOption { type = types.nullOr types.bool; default = null; description = "`snap_respect_gaps_outer true|false`."; };
      borderOverlap = mkOption { type = types.nullOr types.bool; default = null; description = "`snap_border_overlap true|false`."; };
    };

    bar = {
      enable = mkEnableOption "the scroll status bar (a `bar { ... }` block). No block is written at all unless this is true, regardless of the other bar.* options";
      position = mkOption { type = types.nullOr (types.enum [ "top" "bottom" ]); default = null; description = "`position top|bottom`."; };
      statusCommand = mkOption { type = types.nullOr types.str; default = null; example = "while date +'%Y-%m-%d %X'; do sleep 1; done"; description = "`status_command <command>`, run with `sh -c`."; };
      scrollerIndicator = mkOption { type = types.nullOr types.bool; default = null; description = "`scroller_indicator yes|no`."; };
      trailsIndicator = mkOption { type = types.nullOr types.bool; default = null; description = "`trails_indicator yes|no`."; };
      colors = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = { statusline = "#ffffff"; background = "#323232"; };
        description = ''
          A `colors { <key> <value> ... }` sub-block inside `bar`. Keys are scroll-bar's own
          color directive names (`background`, `statusline`, `separator`,
          `focused_background`, `focused_statusline`, `focused_separator`,
          `focused_workspace`, `active_workspace`, `inactive_workspace`, `urgent_workspace`,
          `binding_mode`, `scroller`, ...); see `man 5 scroll-bar`'s COLORS section for the
          full list and argument shape of each.
        '';
      };
    };

    outputs = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          resolution = mkOption { type = types.nullOr types.str; default = null; example = "1920x1080@60Hz"; description = "`output <name> resolution <spec>`."; };
          position = mkOption { type = types.nullOr types.str; default = null; example = "1920 0"; description = "`output <name> position <x> <y>`, written raw as one string."; };
          background = mkOption { type = types.nullOr types.str; default = null; example = "~/wallpaper.png fill"; description = "`output <name> background <file> <mode>` or `<color> solid_color`, written raw."; };
          scale = mkOption { type = types.nullOr num; default = null; description = "`output <name> scale <factor>`."; };
          layout = {
            type = mkOption { type = types.nullOr (types.enum [ "horizontal" "vertical" ]); default = null; description = "`output <name> layout_type horizontal|vertical`."; };
            defaultWidth = mkOption { type = types.nullOr num; default = null; description = "`output <name> layout_default_width <fraction>` — per-output override of layout.defaultWidth."; };
            defaultHeight = mkOption { type = types.nullOr num; default = null; description = "`output <name> layout_default_height <fraction>` — per-output override of layout.defaultHeight."; };
          };
        };
      });
      default = { };
      example = {
        "DP-1" = { resolution = "2560x1440@144Hz"; position = "0 0"; scale = 1.0; };
      };
      description = ''
        Per-output settings, keyed by output name (as reported by `scrollmsg -t get_outputs`
        on the target machine — never bake a specific machine's output name into a default
        here, see README). No entries are emitted by default: an empty attrset means "scroll
        auto-detects everything," which is the only sensible default for a module meant to
        run on any user's hardware.
      '';
    };

    input = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      default = { };
      example = {
        "type:touchpad" = { dwt = "enabled"; tap = "enabled"; natural_scroll = "enabled"; };
        "type:keyboard" = { xkb_layout = "\"eu\""; };
      };
      description = ''
        Raw passthrough to `input <device> { <key> <value>; ... }` blocks. Keys/device names
        are written exactly as given — quote a value yourself (as in the `xkb_layout`
        example) if the directive expects a quoted string. `*` is a valid device name
        (configures all input devices). See `man 5 scroll-input` for the full directive set;
        this module does not model it as an option tree because the set of libinput
        properties is large, mostly orthogonal to scroll itself, and already well documented
        upstream.
      '';
    };

    binds = mkOption {
      type = types.attrsOf (types.nullOr types.str);
      default = { };
      example = { "Mod4+Return" = "exec kitty"; "Mod4+q" = null; };
      description = ''
        Top-level `bindsym <key> <command>` lines. A `null` value emits `unbindsym <key>`
        instead — use it to remove one of scroll's own default bindings without having to
        redeclare the rest of them.
      '';
    };

    modes = mkOption {
      type = types.attrsOf (types.attrsOf (types.nullOr types.str));
      default = { };
      example = {
        wssplit = {
          "1" = "workspace split v 0.25 10; mode default";
          "Escape" = "mode \"default\"";
        };
      };
      description = ''
        Generic i3/sway modal-keymap escape hatch: `mode "<name>" { bindsym <key>
        <command>; ... }` blocks. This is where scroll's own named modes
        (wssplit/jump/filter/modifiers/setsizeh/setsizev/resize/floating/togglesizeh/
        togglesizev/align/fit_size/trailmark/trail/spaces — see this file's header) get
        overridden, if you want different keys than scroll's shipped defaults for them —
        they are NOT separate options, because they are not a scroll-specific mechanism, just
        sway's own generic mode feature. A `null` value inside a mode is skipped, not
        rendered as an unbind (unbinding inside a transient mode block is rarely meaningful);
        omit the key entirely instead.
      '';
    };

    startup = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "swayidle -w timeout 300 'swaylock -f'" ];
      description = ''
        Commands run via `exec <command>` at startup, in the order given. When
        `systemd.enable` is true (the default), scroll's own D-Bus/systemd environment-import
        lines are emitted first, ahead of everything in this list.
      '';
    };

    lua = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        A Lua script for scroll's built-in Lua scripting support, symlinked to
        `~/.config/scroll/scroll.lua` (auto-loaded by scroll if present — see scroll's own
        README for the Lua API). `null`, the default, installs no such file at all.
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Raw scroll config, appended verbatim as the very last thing in the generated file —
        it always wins over every option above, including scroll's own directive ordering
        rules (later lines override earlier ones for most directives).
      '';
    };

    softwareRendering.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Switches the GPU-bound cosmetic layer to sane defaults for a machine with no real
        GPU (a pixman-software-rendering box, e.g. an ASPEED AST2500 server BMC/iGPU): turns
        `animations` off, `decoration.shadow`/`decoration.dim` off, and
        `decoration.borderRadius` to 0. These specific options are GPU-bound work scroll does
        every frame — under pixman's CPU rasterizer that cost lands on a real CPU core
        instead of being nearly free, unlike on an actual GPU. Applied via `mkDefault`, not a
        forced override: set any of `animations.enable`, `decoration.shadow.enable`,
        `decoration.dim.enable` or `decoration.borderRadius` explicitly yourself and your
        value wins, even with this enabled.
      '';
    };
  };

  config = mkMerge [
    (mkIf cfg.softwareRendering.enable {
      programs.scroll.animations.enable = mkDefault false;
      programs.scroll.decoration.shadow.enable = mkDefault false;
      programs.scroll.decoration.dim.enable = mkDefault false;
      programs.scroll.decoration.borderRadius = mkDefault 0;
    })

    (mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.decoration.shadow.offset == null || builtins.length cfg.decoration.shadow.offset == 2;
          message = "programs.scroll.decoration.shadow.offset must be exactly [ x y ] (2 elements).";
        }
      ];

      xdg.configFile."scroll/config".text = renderedConfig;

      xdg.configFile."scroll/scroll.lua" = mkIf (cfg.lua != null) {
        source = cfg.lua;
      };

      systemd.user.targets.scroll-session = mkIf cfg.systemd.enable {
        Unit = {
          Description = "scroll compositor session";
          Documentation = [ "man:systemd.special(7)" ];
          BindsTo = [ "graphical-session.target" ];
          Wants = [ "graphical-session-pre.target" ];
          After = [ "graphical-session-pre.target" ];
        };
      };
    })
  ];
}
