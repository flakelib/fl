{
  description = "nix flakes infrastructure";
  inputs = {
    std.url = "github:flakelib/std";
    fl-config.url = "github:flakelib/fl/config";
  };
  outputs = { self, std, ... }@inputs: let
    flake = self {
      inherit inputs;
      config = {
        name = "flakelib";
        inputs = {
          std = {
            type = self.lib.Fl.Type.Lib;
            lib.namespace = [ ];
          };
          fl-config = {
            type = self.lib.Fl.Type.ConfigV0;
          };
        };
      };
      checks = import ./checks.nix;
      builders = import ./builders.nix;
      devShells = import ./shells.nix;
    };
  in {
    inherit (flake) flakes checks builders devShells;
    lib = import ./lib {
      inherit self std;
    };
    __functor = self: self.lib.callFlake;
  };
}
