{ pkgs, lib, ... }: with lib; let
  flake-check = name: path: pkgs.ci.command {
    name = "${name}-check";
    resolverPath = toString ./resolver;
    libPath = toString ./lib;
    pkgs = toString pkgs.path;
    command = ''
      if [[ $CI_PLATFORM = gh-actions ]]; then
        nix registry add github:flakelib/fl path:$libPath
        nix registry add github:NixOS/nixpkgs path:$pkgs
      fi
      nix flake check ./${path}
    '';
    impure = true;
    environment = [ "CI_PLATFORM" ];
  };
  example-check = flake-check "example-packages" "examples/packages";
  lib-check = flake-check "lib" ".";
  lib-checks = flake-check "checks" "checks";
in {
  name = "flakes.nix";
  ci.version = "nix2.4-broken";
  ci.gh-actions.enable = true;
  cache.cachix.arc.enable = true;
  channels.nixpkgs = "21.11";
  tasks.flakes.inputs = [ lib-check lib-checks example-check ];
}
