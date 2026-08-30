# home/ipc-compat.nix — integrate cscroll's strict-Sway IPC runtime helper.
#
# This module owns Nix integration only. The proxy implementation, layout-schema
# translation, IPC framing, upstream discovery and runtime tests live in cscroll's
# installed `scroll-swayipc-compat` program. In particular, this file contains no
# generated Python, workspace synthesis, workspace-ID rewriting, empty-event
# suppression or favourites policy.
{ self }:
{ lib, config, pkgs, ... }:
let
  cfg = config.programs.scroll.ipcCompat;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.scroll;
  favoriteArguments = lib.concatMap
    (workspace: [ "--favorite" (toString workspace) ])
    cfg.favorites;
in
{
  options.programs.scroll.ipcCompat = {
    enable = lib.mkEnableOption ''
      cscroll's strict-Sway IPC compatibility helper for clients whose
      deserializer rejects Scroll's native horizontal and vertical layout names
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression
        "inputs.nixscroll.packages.\${pkgs.stdenv.hostPlatform.system}.scroll";
      description = ''
        The cscroll package that provides bin/scroll-swayipc-compat. The package
        is referenced by absolute store path; the helper never depends on PATH
        and this module never renders a copy of its implementation.
      '';
    };

    executable = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${cfg.package}/bin/scroll-swayipc-compat";
      description = "Absolute path to cscroll's packaged IPC helper.";
    };

    socketName = lib.mkOption {
      type = lib.types.str;
      default = "scroll-swaycompat.sock";
      description = "Socket basename, created inside XDG_RUNTIME_DIR.";
    };

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "scroll-ipc-compat";
      description = ''
        Name of the generated systemd user service. Clients can read this value
        when declaring Requires= and After= rather than restating the name.
      '';
    };

    favorites = lib.mkOption {
      type = lib.types.listOf lib.types.ints.unsigned;
      default = [ ];
      apply = lib.unique;
      example = [ 0 1 2 3 4 5 ];
      description = ''
        Non-negative numbered workspaces that the cscroll helper should retain for
        strict workspace clients. The helper rekeys real numbered workspaces,
        synthesizes absent favourites, and suppresses their empty events.
        Leave empty when the client implements its own pinned-workspace policy.
      '';
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "%t/${cfg.socketName}";
      description = ''
        Proxy socket for a strict client, using systemd's %t runtime-directory
        specifier. A client sets SWAYSOCK to this value and must also unset the
        variables listed by unsetVariables.
      '';
    };

    unsetVariables = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [ "SCROLLSOCK" "I3SOCK" ];
      description = ''
        Variables a strict client's unit must unset. Scroll exports SCROLLSOCK,
        and Sway IPC libraries probe it before the SWAYSOCK value pointing at the
        proxy; leaving it set silently bypasses the helper.
      '';
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = lib.concatStringsSep " " (
        [ cfg.executable ] ++ favoriteArguments ++ [ cfg.socketPath ]
      );
      description = ''
        Complete command for the proxy. Published for consumers that declare the
        service through another session-service owner and set enableService=false.
      '';
    };

    enableService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether this module declares the systemd user service. Disable only when
        another session integration declares the same command and lifecycle.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.enableService) {
    systemd.user.services.${cfg.serviceName} = {
      Unit = {
        Description = "Strict-Sway IPC compatibility for Scroll";
        Documentation = [ "man:scroll-swayipc-compat(1)" ];
        PartOf = [ "graphical-session.target" ];

        # Clients are commonly WantedBy=graphical-session.target and ordered
        # after this unit. Ordering the helper after that same target closes a
        # cycle through those clients; graphical-session-pre.target does not.
        After = [ "graphical-session-pre.target" ];
      };
      Service = {
        # cscroll sends READY=1 only after binding the proxy socket, so After=
        # means the path accepts connections rather than merely being exec'd.
        Type = "notify";
        ExecStart = cfg.command;
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
