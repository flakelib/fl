{ self, std }@inputs: builtins.mapAttrs (_: f: import f inputs) {
  context = ./context.nix;
  flake = ./flake.nix;
  resolver = ./resolver.nix;
  util = ./util.nix;
}
