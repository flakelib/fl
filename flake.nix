{
  inputs = {
    std.url = "github:flakelib/std";
  };
  outputs = { self, std, ... }@inputs: let
    flake = self {
      inherit inputs;
      config = {
        name = "flakelib";
      };
      checks = import ./checks.nix;
      builders = import ./builders.nix;
    };
  in {
    inherit (flake) flakes checks builders;
    lib = import ./lib {
      inherit self std;
    };
    __functor = self: self.lib.callFlake;
  };
}
