{ pkgs, lib, ... }: with lib; let
  flake-check = name: path: pkgs.ci.command {
    name = "${name}-check";
    command = ''
      nix flake check ./${path}
    '';
    impure = true;
  };
  flakegen-check = flake-check "flakegen" "flakegen";
  example-check = flake-check "example-packages" "examples/packages";
  lib-check = flake-check "lib" "lib";
in {
  name = "flakes.nix";
  ci.version = "nix2.4";
  ci.gh-actions.enable = true;
  gh-actions.env.GITHUB_TOKEN = "\${{ secrets.GITHUB_TOKEN }}";
  cache.cachix.arc.enable = true;
  channels.nixpkgs = "21.11";
  tasks.flakes.inputs = [ flakegen-check lib-check example-check ];
}
