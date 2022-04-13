{ pkgs, lib, ... }: with lib; let
  flake-check = name: path: pkgs.ci.command {
    name = "${name}-check";
    resolverPath = toString ./resolver;
    libPath = toString ./lib;
    pkgs = toString pkgs.path;
    command = ''
      if [[ $CI_PLATFORM = gh-actions ]]; then
        nix registry add flakes-std github:arcnmx/nix-std
        nix registry add flakes-resolver path:$resolverPath
        nix registry add flakes-lib path:$libPath
        nix registry add nixpkgs path:$pkgs
      fi
      nix flake check ./${path}
    '';
    impure = true;
    environment = [ "CI_PLATFORM" ];
  };
  flakegen-check = flake-check "flakegen" "flakegen";
  example-check = flake-check "example-packages" "examples/packages";
  lib-check = flake-check "lib" "lib";
  lib-checks = flake-check "lib-checks" "lib/checks";
in {
  name = "flakes.nix";
  ci.version = "nix2.4-broken";
  ci.gh-actions.enable = true;
  cache.cachix.arc.enable = true;
  channels.nixpkgs = "21.11";
  tasks.flakes.inputs = [ flakegen-check lib-check lib-checks example-check ];
}
