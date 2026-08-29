# Boot an isolated NixOS VM and exercise the packaged cscroll runtime. Every
# IPC command is bound to a socket proven to have appeared after this VM's own
# compositor started; the harness never relies on sway/scroll socket fallback.
{ pkgs, nixosModule, scrollPackage }:
let
  config = pkgs.writeText "cscroll-vm.conf" ''
    workspace 1
  '';
in
pkgs.testers.nixosTest {
  name = "nixscroll-runtime";

  nodes.machine = { ... }: {
    imports = [ nixosModule ];
    programs.scroll = {
      enable = true;
      package = scrollPackage;
    };
    environment.systemPackages = [
      # The packaged Scroll wrapper starts a private session bus when no
      # DBUS_SESSION_BUS_ADDRESS is inherited. The VM needs both
      # dbus-run-session and the dbus-daemon it execs.
      pkgs.dbus
      pkgs.jq
    ];
    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("the complete product is materialized"):
        machine.succeed("test -x ${scrollPackage}/bin/scroll")
        machine.succeed("test -x ${scrollPackage}/bin/scrollmsg")
        machine.succeed("test -x ${scrollPackage}/bin/scroll-swayipc-compat")
        machine.succeed("test -f ${scrollPackage}/share/xdg-desktop-portal/scroll-portals.conf")
        machine.succeed("command -v swaybg")
        machine.succeed("command -v wlr-randr")
        machine.succeed("test -x ${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr")
        machine.succeed("command -v Xwayland")

    with subtest("the exact packaged binary accepts the fixture"):
        machine.succeed("install -d -m 0700 /run/cscroll-validate")
        machine.succeed("XDG_RUNTIME_DIR=/run/cscroll-validate WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 ${scrollPackage}/bin/scroll --validate -c ${config} 2>&1 | tee /tmp/validate.log")
        machine.fail("grep -E 'Unknown/invalid|Error on line|Failed to parse' /tmp/validate.log")

    with subtest("a Pixman headless compositor owns a new isolated socket"):
        machine.succeed("install -d -m 0700 /run/cscroll-vm")
        machine.succeed("find /run/cscroll-vm -maxdepth 1 -type s -name 'scroll-ipc.*.sock' -print | sort > /run/cscroll-before")
        machine.succeed(
            "systemd-run --unit=cscroll-vm "
            "--property=Environment=XDG_RUNTIME_DIR=/run/cscroll-vm "
            "--property=Environment=WLR_BACKENDS=headless "
            "--property=Environment=WLR_HEADLESS_OUTPUTS=1 "
            "--property=Environment=WLR_RENDERER=pixman "
            "--property=Environment=WLR_LIBINPUT_NO_DEVICES=1 "
            "${scrollPackage}/bin/scroll -c ${config}"
        )
        # Stop immediately when the unit fails instead of spending the test's
        # full timeout waiting for a socket a dead compositor cannot create.
        machine.wait_until_succeeds(
            "test $(find /run/cscroll-vm -maxdepth 1 -type s -name 'scroll-ipc.*.sock' | wc -l) -eq 1 "
            "|| systemctl is-failed --quiet cscroll-vm.service",
            timeout=60,
        )
        machine.succeed("systemctl is-active --quiet cscroll-vm.service")
        machine.succeed(
            "find /run/cscroll-vm -maxdepth 1 -type s -name 'scroll-ipc.*.sock' -print | sort "
            "| comm -13 /run/cscroll-before - > /run/cscroll-owned-sockets"
        )
        machine.succeed("test $(wc -l < /run/cscroll-owned-sockets) -eq 1")
        machine.succeed("test -S $(cat /run/cscroll-owned-sockets)")
        machine.succeed("systemctl is-active cscroll-vm.service")
        machine.succeed("journalctl -u cscroll-vm.service | grep -i pixman")

    with subtest("IPC reaches only the proven VM compositor"):
        machine.succeed(
            "socket=$(cat /run/cscroll-owned-sockets); "
            "SCROLLSOCK=$socket SWAYSOCK=$socket "
            "${scrollPackage}/bin/scrollmsg -t get_outputs | jq -e 'length == 1'"
        )
        machine.succeed(
            "socket=$(cat /run/cscroll-owned-sockets); "
            "SCROLLSOCK=$socket SWAYSOCK=$socket "
            "${scrollPackage}/bin/scrollmsg workspace 1"
        )
        machine.succeed(
            "socket=$(cat /run/cscroll-owned-sockets); "
            "SCROLLSOCK=$socket SWAYSOCK=$socket "
            "${scrollPackage}/bin/scrollmsg -t get_workspaces "
            "| tee /run/cscroll-direct.json "
            "| jq -e 'any(.[]; .layout == \"horizontal\")'"
        )

    with subtest("the packaged compatibility bridge rewrites only its schema seam"):
        machine.succeed(
            "socket=$(cat /run/cscroll-owned-sockets); "
            "systemd-run --unit=cscroll-compat "
            "--property=Environment=XDG_RUNTIME_DIR=/run/cscroll-vm "
            "${scrollPackage}/bin/scroll-swayipc-compat "
            "/run/cscroll-vm/compat.sock --upstream $socket"
        )
        machine.wait_until_succeeds("test -S /run/cscroll-vm/compat.sock")
        machine.succeed(
            "SCROLLSOCK= SWAYSOCK=/run/cscroll-vm/compat.sock "
            "${scrollPackage}/bin/scrollmsg -t get_workspaces "
            "| tee /run/cscroll-proxy.json "
            "| jq -e 'any(.[]; .layout == \"splith\")'"
        )
        machine.succeed(
            "jq 'map(.layout = \"IGNORED\")' /run/cscroll-direct.json > /run/cscroll-direct-normalized; "
            "jq 'map(.layout = \"IGNORED\")' /run/cscroll-proxy.json > /run/cscroll-proxy-normalized; "
            "cmp /run/cscroll-direct-normalized /run/cscroll-proxy-normalized"
        )

    machine.succeed("systemctl stop cscroll-compat.service cscroll-vm.service")
  '';
}
