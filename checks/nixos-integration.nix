# Evaluate the NixOS module both with and without nixdesktop's optional
# compositor registry. Installation must remain standalone, while composition
# registers the exact same complete Scroll descriptor as system-manager.
{ pkgs, lib ? pkgs.lib, nixosModule }:
let
  fakeCscroll = pkgs.writeShellScriptBin "scroll" "exit 0";

  baseStubs = { lib, ... }: {
    options = {
      environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
      services.displayManager.sessionPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
    };
  };

  desktopStub = { lib, ... }: {
    options.nixdesktop.launcher.compositors = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };

  evaluate = modules: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [ baseStubs nixosModule ] ++ modules ++ [{
      programs.scroll = {
        enable = true;
        package = fakeCscroll;
      };
    }];
  }).config;

  standalone = evaluate [ ];
  composed = evaluate [ desktopStub ];
  descriptor = composed.nixdesktop.launcher.compositors.scroll;

  results = {
    "standalone use installs the selected runtime without requiring nixdesktop" =
      lib.elem fakeCscroll standalone.environment.systemPackages
      && standalone.services.displayManager.sessionPackages == [ fakeCscroll ];
    "composition registers the complete neutral-to-Scroll translation" =
      toString descriptor.package == toString fakeCscroll
      && descriptor.command == "scroll"
      && descriptor.deviceEnvironment == [ "WLR_DRM_DEVICES" ]
      && descriptor.rendererEnvironment.software.WLR_RENDERER == "pixman"
      && descriptor.headlessEnvironment.WLR_BACKENDS == "headless"
      && descriptor.supportsHeadless
      && descriptor.supportsVirtualOutputs
      && !descriptor.supportsNotify
      && descriptor.currentDesktop == "scroll";
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else throw ''
  nixscroll: the NixOS integration is broken. Failing assertions:
  ${lib.concatMapStringsSep "\n" (failure: "  - ${failure}") failed}
''
