{
  inputs = {
    nixpkgs.url = "nixpkgs"; # TODO: replace with nixlib if needed
  };
  outputs = { self, nixpkgs, ... }@inputs: let
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
      callPackage = self.lib.makeCallPackage {
        buildConfig = null;
        scope = {
          global = self.lib;
          inputs = {
            nixpkgs = {
              inherit (nixpkgs) lib;
            };
            flakes = {
              inherit (self) lib;
            };
          };
        };
        inputs = {
          inherit nixpkgs;
          flakes = self;
        };
      };
    } // import ./callpackage.nix {
      lib = nixpkgs.lib;
      self'lib = self.lib;
    } // import ./callflake.nix {
      lib = nixpkgs.lib;
      self'lib = self.lib;
    };
    __functor = self: self.lib.callFlake;
  };
}
