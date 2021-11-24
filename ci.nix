{ pkgs, lib, ... }: with lib; let
  flakegen-check = pkgs.ci.command {
    name = "flakegen-check";
    command = ''
      ${pkgs.nix_2_4}/bin/nix flake check ./flakegen
    '';
    impure = true;
  };
in {
  name = "flakes.nix";
  ci.gh-actions.enable = true;
  cache.cachix.arc.enable = true;
  tasks.flakegen.inputs = singleton flakegen-check;
}
