{ flake-utils, callPackage, lib, flakegen-lib, flakegen-build }: let
  inherit (lib) flip mapAttrs;
  flakeConfig = removeAttrs (import ./flake.nix) [ "outputs" ];
  flake = flakegen-lib.mkFlake flakeConfig;
  generated = flakegen-build.generate {
    inherit flake;
  };
in mapAttrs (_: flip callPackage { }) {
  flakegen = {
    runCommand
  , nix-check
  , path
  }: runCommand "flakegen" {
    nativeBuildInputs = [ nix-check ];
    inherit generated;
    outputsNix = "inputs: { }";
    passAsFile = [ "outputsNix" ];
    flakeutils = flake-utils;
    pkgs = path;
  } ''
    cat $generated > flake.nix
    cat $outputsNixPath > outputs.nix
    nix flake check \
      --override-input flake-utils path:$flakeutils \
      --override-input nixpkgs path:$pkgs \
      --no-build
    mkdir $out
    mv flake.nix outputs.nix $out/
  '';
}
