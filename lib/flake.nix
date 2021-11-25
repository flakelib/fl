{
  inputs = {
    nixpkgs.url = "nixpkgs"; # TODO: replace with nixlib if needed
  };
  outputs = { self, nixpkgs, ... }@inputs: {
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
    flakes = {
      config = {
        aliases = [ "fl" ];
      };
      import = { buildConfig ? null }: self;
    };
    checks = import ./checks.nix {
      pkgs = import nixpkgs { };
      self'lib = self.lib;
    };
  };
}
