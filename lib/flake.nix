{
  inputs = {
    resolver = {
      url = "flakes-resolver";
      inputs.std.follows = "std";
    };
    std.url = "flakes-std";
  };
  outputs = { self, resolver, std, ... }@inputs: let
    flake = self {
      inherit inputs;
      config = {
        aliases = [ "fl" ];
      };
      checks = import ./checks.nix;
      builders = import ./builders.nix;
    };
  in {
    inherit (flake) flakes checks builders;
    lib = import ./lib {
      inherit self resolver std;
    };
    __functor = self: self.lib.callFlake;
  };
}
