{
  description = "nixscroll — declarative config generation for scroll (a scrolling/PaperWM-style fork of sway), plus the packaging and system wiring it needs since it isn't in nixpkgs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Runtime source and Nix integration are separate products. cscroll is deliberately a plain
    # source input: it contains Scroll, scrollmsg and tightly coupled runtime repairs, but no Nix
    # module. The public source is pinned in flake.lock; no machine-local source
    # path or independent upstream Scroll revision may bypass this boundary.
    cscroll = {
      url = "github:corbet-labs/cscroll";
      flake = false;
    };

    # github:Diax170/scroll-flake remains the maintained build recipe. Its two source inputs both
    # follow cscroll, so every package it exposes is built from our one runtime product rather than
    # reaching around the boundary to dawsers/scroll. Full credit to Diax170 for the packaging.
    scroll-flake = {
      url = "github:Diax170/scroll-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.scroll-git.follows = "cscroll";
      inputs.scroll-stable.follows = "cscroll";
    };

    # nixhost IS an input, for exactly one thing: `lib.probeFact` (github:julian-corbet/
    # nixhost-corbet-ch, `lib/facts.nix`) -- the shared, plain-function fix for the
    # cross-namespace defensive-read defect class `home/scroll.nix`'s own
    # `nixdesktopStartupProbe` leans on (see nixhost's own `lib/facts.nix` header).
    # `probeFact` is closed over as a plain function argument (below), never `_module.args`, so
    # a consumer importing `homeManagerModules.scroll` sees an ordinary module function and never
    # needs to know `nixhost` exists. This is unrelated to how `nixdesktop.startup` itself is
    # read: that stays a defensive, zero-flake-dependency probe -- only the `probeFact`
    # MECHANISM is consumed from nixhost.
    nixhost = {
      url = "github:julian-corbet/nixhost-corbet-ch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, cscroll, scroll-flake, nixhost, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      runtimeManifest =
        let
          parsed = builtins.fromTOML
            (builtins.readFile "${cscroll}/runtime-components.toml");
        in
        assert parsed.schema == 1;
        assert builtins.isList parsed.component;
        parsed;

      # `probeFact` closed over here, before the module system ever sees the result -- see the
      # `nixhost` input comment above. The exported value is a plain home-manager module function
      # taking the usual `{ lib, config, ... }`; nothing about consuming it changes.
      scrollModule = import ./home/scroll.nix { inherit (nixhost.lib) probeFact; };
      ipcCompatModule = import ./home/ipc-compat.nix { inherit self; };
      descriptorFor = import ./lib/compositor-descriptor.nix;
    in
    {
      # ── PACKAGING ───────────────────────────────────────────────────────────────────────────
      # Keep scroll-flake's working Sway/wlroots recipe and replace only its source (through the
      # input follows above). The scroll executable gets a deliberately narrow Mesa environment:
      # a Nix-built compositor cannot otherwise find its EGL vendor and DRI drivers when launched
      # on Arch. This does not wrap scrollmsg or the IPC helper and deliberately does not guess a
      # hardware-specific Vulkan ICD. cscroll's temporary IPC helper is a Python program installed
      # by the Meson build. Python is a native build input solely so patchShebangs can write one
      # absolute store interpreter into that helper; it is not added to Scroll's runtime PATH.
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          mesaEnvironment = {
            eglVendor = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
            libglDrivers = "${pkgs.mesa}/lib/dri";
          };
          wrappedScroll = scroll-flake.packages.${system}.default.override {
            # This hook is part of nixpkgs' sway wrapper and therefore affects only
            # bin/scroll. Referencing pkgs.mesa here also attaches the driver closure.
            extraSessionCommands = ''
              export __EGL_VENDOR_LIBRARY_FILENAMES="${mesaEnvironment.eglVendor}"
              export LIBGL_DRIVERS_PATH="${mesaEnvironment.libglDrivers}"
            '';
          };
          scroll = wrappedScroll.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
            passthru = (old.passthru or { }) // {
              # A small, evaluable packaging contract for checks and downstream diagnostics.
              nixscrollMesaEnvironment = mesaEnvironment;
            };
            postFixup = (old.postFixup or "") + ''
              helper="$out/bin/scroll-swayipc-compat"
              if [[ ! -x "$helper" ]]; then
                echo "nixscroll: cscroll did not install $helper" >&2
                exit 1
              fi
              # scroll-flake's outer package is an lndir tree over the unwrapped
              # build. Copy only this helper out of that tree before patching;
              # patchShebangs intentionally does not rewrite a store symlink.
              if [[ -L "$helper" ]]; then
                helperSource="$(readlink -f "$helper")"
                unlink "$helper"
                cp "$helperSource" "$helper"
                chmod u+w "$helper"
              fi
              patchShebangs "$helper"
              expected='#!${pkgs.python3}/bin/python3'
              actual="$(head -n 1 "$helper")"
              if [[ "$actual" != "$expected" ]]; then
                echo "nixscroll: unexpected IPC helper interpreter: $actual" >&2
                exit 1
              fi
            '';
          });
        in
        {
          inherit scroll;
          default = scroll;
        });

      # ── SYSTEM SIDE ───────────────────────────────────────────────────────────────────────
      # Installs the package plus every required external component from
      # cscroll's manifest and registers the wayland-sessions entry it ships.
      # Config generation (below) remains a separate concern.
      nixosModules.scroll = import ./modules/nixos.nix {
        inherit self runtimeManifest descriptorFor;
      };
      nixosModules.default = self.nixosModules.scroll;

      # Arch/CachyOS plane. Registers the cscroll derivation and full Scroll launch descriptor
      # with nixdesktop; required external components from cscroll's manifest
      # are delegated to pacman as one removable bundle. Config
      # generation stays in homeManagerModules.scroll on both planes.
      systemManagerModules.scroll = import ./modules/system-manager.nix {
        inherit self runtimeManifest descriptorFor;
      };
      systemManagerModules.default = self.systemManagerModules.scroll;

      # ── CONFIG GENERATION ────────────────────────────────────────────────────────────────
      # Writes ~/.config/scroll/config from structured options (namespace: programs.scroll).
      # Installs nothing — see README. Reads no package by default; the one place it optionally
      # does (see `package` option in home/scroll.nix) never adds anything to home.packages.
      homeManagerModules = {
        scroll = scrollModule;
        default = scrollModule;

        # The proxy implementation is part of cscroll. This integration module only selects that
        # packaged executable and declares its optional user unit.
        ipcCompat = ipcCompatModule;
      };

      # ── CHECKS ────────────────────────────────────────────────────────────────────────────
      # `nix flake check` does NOT evaluate `homeManagerModules` or `systemManagerModules` — it
      # lists them as unchecked and moves on. Since config generation is what this repo is FOR,
      # a green `flake check` here covered the package output and the NixOS module while
      # proving nothing at all about home/scroll.nix. This closes that gap by evaluating the module
      # for real against a minimal home-manager stub.
      #
      # Scoped to the `nixdesktop.startup` seam rather than being a full golden-file test of the
      # rendered config: the seam is the part with a SILENT failure mode (a populated contract with
      # no reader renders nothing and errors nowhere), and silent failures are what a check earns
      # its keep on.
      #
      # A malformed bindsym does NOT surface the moment scroll starts: scroll logs a rejected
      # directive to stderr and carries on, both at startup and under `--validate`, which exits 0
      # regardless. A bad directive surfaces nowhere unless something greps for it -- which is
      # why `config-accepted` below exists.
      checks = forAllSystems (system: {
        startup-contract = import ./checks/startup-contract.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit scrollModule;
        };
        # Evaluates the IPC integration module and proves it references cscroll's executable rather
        # than embedding runtime code or workspace policy in Nix.
        ipc-compat = import ./checks/ipc-compat.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit ipcCompatModule;
          scrollPackage = self.packages.${system}.scroll;
        };
        # Evaluates the nixdisplay.layouts/nixdisplay.monitors/nixdesktop.sessions translation --
        # transform inversion, identity-with-spaces quoting, alias fan-out, disabled outputs,
        # mode/modeline rendering, and the permittedDrmDevices passthrough. Nix inspecting Nix, same
        # caveat as startup-contract: it proves this module renders what it INTENDS, not that
        # scroll agrees -- config-accepted below is the one that asks the real binary.
        layout-outputs = import ./checks/layout-outputs.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit scrollModule;
        };
        # Evaluates the nixdesktop.sessions.<name>.virtualOutputs -> create_output/output-mode IPC
        # translation: the HEADLESS-<N+1> numbering offset scroll's own FALLBACK output forces (a
        # measured fact about the real dawsers/scroll source, not a convention — see the check's
        # own header and home/scroll.nix's `virtualOutputLines` comment), and that create_output
        # and its mode line are chained as ONE scrollmsg argument rather than racing across two
        # separate exec'd processes.
        virtual-outputs = import ./checks/virtual-outputs.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit scrollModule;
        };
        # Runs the REAL binary against this module's own output. Everything else here is Nix
        # inspecting Nix, which cannot notice that scroll disagrees -- and it did, about ten
        # directives. See the check's header for why it greps stderr instead of trusting the
        # exit code, and note this is the one check that costs a scroll build.
        config-accepted = import ./checks/config-accepted.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          scroll = self.packages.${system}.scroll;
          inherit scrollModule;
        };
        # The Arch plane, which `nix flake check` likewise never evaluates on its own. Its whole
        # output is WHICH OF TWO PACKAGE LISTS each name lands in, and on this platform the wrong
        # answer in one direction fails the host's entire pacman transaction -- see the check's own
        # header.
        arch-packages = import ./checks/arch-packages.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          systemManagerModule = self.systemManagerModules.scroll;
        };
        nixos-integration = import ./checks/nixos-integration.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          nixosModule = self.nixosModules.scroll;
        };
      } // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        runtime-vm = import ./checks/runtime-vm.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          nixosModule = self.nixosModules.scroll;
          scrollPackage = self.packages.${system}.scroll;
        };
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
