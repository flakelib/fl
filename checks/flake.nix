{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    std.url = "github:flakelib/std";
    flakelib = {
      url = "../";
      inputs = {
        std.follows = "std";
      };
    };
    flakegen = {
      url = "github:flakelib/flakegen";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        std.follows = "std";
        flakelib.follows = "flakelib";
      };
    };
  };
  outputs = { flakelib, std, nixpkgs, ... }@inputs: flakelib {
    inherit inputs;
    systems = flakelib.lib.System.Supported.tier2 ++ [
      {
        localSystem = "x86_64-linux";
        crossSystem = nixpkgs.lib.systems.elaborate nixpkgs.lib.systems.examples.avr;
      }
      {
        localSystem = "x86_64-linux";
        crossSystem = nixpkgs.lib.systems.elaborate nixpkgs.lib.systems.examples.aarch64-multiplatform;
      }
    ];
    config = {
      name = "fl-checks";
      inputs = {
        std.aliases = [ "std2" ];
      };
    };
    checks = import ./checks.nix;
    packages = import ./packages.nix;
    legacyPackages = { runCommand }: {
      recursive-merge-test = {
        a = 1;
        b = 2;
      };
      merge-override-test = runCommand "override-test-broken" { } "false";
    };
    builders = { }: {
      recursive-merge-test = {
        a = 0;
        c = 3;
      };
    };
  };
}
