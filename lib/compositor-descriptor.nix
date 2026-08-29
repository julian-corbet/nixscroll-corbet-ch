package: {
  inherit package;
  command = "scroll";
  deviceEnvironment = [ "WLR_DRM_DEVICES" ];
  rendererEnvironment = {
    auto = { };
    hardware = { };
    software.WLR_RENDERER = "pixman";
  };
  headlessEnvironment.WLR_BACKENDS = "headless";
  supportsHeadless = true;
  supportsVirtualOutputs = true;
  supportsNotify = false;
  currentDesktop = "scroll";
}
