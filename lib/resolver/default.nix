{ self, std }@inputs: builtins.mapAttrs (_: f: import f inputs) {
  Context = ./context.nix;
  flake = ./flake.nix;
  resolver = ./resolver.nix;
  util = ./util.nix;
}
