{ pkgs, lib, ... }: with lib; let
  nix24 = pkgs.writeShellScriptBin "nix" ''
    ARGS=(
      --extra-experimental-features "nix-command flakes ca-derivations recursive-nix"
    )
    if [[ -n ''${GITHUB_TOKEN-} ]]; then
      ARGS+=(--access-tokens "github.com=$GITHUB_TOKEN")
    fi
    ${pkgs.nix_2_4}/bin/nix "''${ARGS[@]}" "$@"
  '';
  flakegen-check = pkgs.ci.command {
    name = "flakegen-check";
    command = ''
      ${nix24}/bin/nix flake check ./flakegen
    '';
    impure = true;
  };
in {
  name = "flakes.nix";
  ci.gh-actions.enable = true;
  cache.cachix.arc.enable = true;
  channels.nixpkgs = "21.11";
  tasks.flakegen.inputs = singleton flakegen-check;
}
