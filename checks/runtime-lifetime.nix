# Exercise the real compositor with ASan. Source regressions live in cscroll;
# this repository owns the build recipe and makes them a required flake check.
{ pkgs, scrollUnwrapped }:
scrollUnwrapped.overrideAttrs (old: {
  pname = "cscroll-runtime-lifetime";
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    (pkgs.python3.withPackages (python: [ python.pytest ]))
  ];
  mesonBuildType = "debugoptimized";
  mesonFlags = (old.mesonFlags or [ ]) ++ [
    "-Db_sanitize=address"
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export XDG_RUNTIME_DIR="$(mktemp -d)"
    export WLR_RENDERER=pixman
    unset DISPLAY WAYLAND_DISPLAY SWAYSOCK I3SOCK SCROLLSOCK
    cd ..
    # Run serially; pytest.ini's developer default requires pytest-xdist.
    python3 -m pytest tests --scroll build/sway/scroll -q -o addopts=
    cd build
    runHook postCheck
  '';
  installPhase = ''
    touch "$out"
  '';
  # The output records the check result; no instrumented executable is shipped.
  separateDebugInfo = false;
  dontFixup = true;
})
