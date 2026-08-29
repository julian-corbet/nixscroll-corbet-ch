# Exercise the exact packaged cscroll wrapper on the real TTY/DRM backend. The
# three Mesa paths begin poisoned; only the wrapper can replace them with its
# Nix Mesa closure before wlroots creates the GBM allocator.
{ pkgs, scrollPackage }:
let
  config = pkgs.writeText "cscroll-tty-vm.conf" ''
    workspace 1
  '';
in
pkgs.testers.nixosTest {
  name = "nixscroll-tty-gpu-runtime";

  nodes.machine = { ... }: {
    boot.kernelModules = [ "virtio_gpu" ];
    hardware.graphics.enable = true;
    services.seatd.enable = true;

    users.users.cscroll-test = {
      isNormalUser = true;
      uid = 1000;
      group = "users";
      extraGroups = [
        "input"
        "seat"
        "video"
        "render"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /run/user/1000 0700 cscroll-test users -"
    ];
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;

    systemd.services.cscroll-tty-vm = {
      description = "Disposable cscroll TTY GPU-wrapper test";
      after = [
        "seatd.service"
        "systemd-user-sessions.service"
      ];
      requires = [ "seatd.service" ];
      serviceConfig = {
        Type = "simple";
        User = "cscroll-test";
        Group = "users";
        SupplementaryGroups = [
          "input"
          "seat"
          "video"
          "render"
        ];
        PAMName = "login";
        TTYPath = "/dev/tty1";
        StandardInput = "tty-force";
        StandardOutput = "journal";
        StandardError = "journal";
        TTYReset = true;
        TTYVHangup = true;
        UtmpIdentifier = "tty1";
        UtmpMode = "user";
        Environment = [
          "XDG_RUNTIME_DIR=/run/user/1000"
          "XDG_SESSION_TYPE=wayland"
          "XDG_SESSION_DESKTOP=scroll"
          "XDG_CURRENT_DESKTOP=scroll"
          "LIBSEAT_BACKEND=seatd"
          "WLR_DRM_DEVICES=/dev/dri/card0"
          "WLR_LIBINPUT_NO_DEVICES=1"
          "__EGL_VENDOR_LIBRARY_FILENAMES=/does-not-exist"
          "LIBGL_DRIVERS_PATH=/does-not-exist"
          "GBM_BACKENDS_PATH=/does-not-exist"
        ];
        ExecStart = "${scrollPackage}/bin/scroll --debug -c ${config}";
      };
    };

    environment.systemPackages = [
      scrollPackage
      pkgs.jq
    ];

    virtualisation = {
      memorySize = 4096;
      cores = 4;
      qemu.options = [ "-device virtio-vga" ];
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("seatd.service")

    with subtest("the VM exposes one isolated DRM device"):
        machine.succeed("test -c /dev/dri/card0")
        machine.succeed(
            "find /run/user/1000 -maxdepth 1 -type s -name 'scroll-ipc.*.sock' "
            "-print | sort > /run/cscroll-tty-before"
        )

    with subtest("the packaged wrapper reaches a working GBM allocator"):
        machine.succeed("systemctl start --no-block cscroll-tty-vm.service")
        machine.wait_until_succeeds(
            "test $(find /run/user/1000 -maxdepth 1 -type s "
            "-name 'scroll-ipc.*.sock' | wc -l) -eq 1 "
            "|| systemctl is-failed --quiet cscroll-tty-vm.service",
            timeout=60,
        )
        machine.succeed("systemctl is-active --quiet cscroll-tty-vm.service")
        machine.fail(
            "journalctl -b -o cat --no-pager | "
            "grep -E 'MESA-LOADER: failed|gbm_create_device failed|Failed to create allocator'"
        )
        machine.succeed(
            "find /run/user/1000 -maxdepth 1 -type s -name 'scroll-ipc.*.sock' "
            "-print | sort | comm -13 /run/cscroll-tty-before - "
            "> /run/cscroll-tty-owned-sockets"
        )
        machine.succeed("test $(wc -l < /run/cscroll-tty-owned-sockets) -eq 1")

    with subtest("IPC reaches the physical-backend compositor"):
        machine.succeed(
            "socket=$(cat /run/cscroll-tty-owned-sockets); "
            "sudo -u cscroll-test env XDG_RUNTIME_DIR=/run/user/1000 "
            "SCROLLSOCK=$socket SWAYSOCK=$socket "
            "${scrollPackage}/bin/scrollmsg -t get_outputs "
            "| tee /run/cscroll-tty-outputs.json | jq -e 'length >= 1'"
        )

    machine.succeed("systemctl stop cscroll-tty-vm.service")
  '';
}
