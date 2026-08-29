# Inspect the final executable wrapper that system-manager launches on Arch.
# Metadata alone did not catch a missing GBM backend path: the compositor
# reached Mesa, then failed its allocator because /run/opengl-driver exists on
# NixOS but not on the foreign host.
{ pkgs, scrollPackage }:
let
  mesa = scrollPackage.nixscrollMesaEnvironment;
in
pkgs.runCommand "nixscroll-wrapper-contract" { } ''
  wrapper=${scrollPackage}/bin/.scroll-wrapped
  test -x "$wrapper"
  grep -F 'export __EGL_VENDOR_LIBRARY_FILENAMES="${mesa.eglVendor}"' "$wrapper"
  grep -F 'export LIBGL_DRIVERS_PATH="${mesa.libglDrivers}"' "$wrapper"
  grep -F 'export GBM_BACKENDS_PATH="${mesa.gbmBackends}"' "$wrapper"
  touch "$out"
''
