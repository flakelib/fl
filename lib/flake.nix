{
  inputs = {
    nixpkgs.url = "github:arcnmx/nixpkgs-lib";
    resolver = {
      url = "flakes-resolver";
      inputs.std.follows = "std";
    };
    std.url = "flakes-std";
  };
  outputs = { self, nixpkgs, resolver, std, ... }@inputs: let
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
    lib = import ./lib.nix {
      inherit (nixpkgs) lib;
    } // {
      callFlake = import ./callflake.nix {
        std = std.lib;
        self'lib = self.lib;
        resolver = resolver.lib;
      };
    };
    __functor = self: self.lib.callFlake;
  };
}
