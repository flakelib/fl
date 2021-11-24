{
  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, flake-utils, nixpkgs, ... }@inputs: let
    outputs = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages = { };
      legacyPackages = {
        callPackage = pkgs.newScope (
          self.legacyPackages.${system}.build // self.packages.${system}
        );
        build = import ./build.nix {
          inherit (nixpkgs) lib;
          inherit (self.legacyPackages.${system}) callPackage;
        };
      };
      checks = import ./checks.nix {
        inherit (self.legacyPackages.${system}) callPackage;
        inherit (nixpkgs) lib;
        inherit flake-utils;
        flakegen-lib = self.lib;
        flakegen-build = self.legacyPackages.${system}.build;
      };
    };
  in flake-utils.lib.eachDefaultSystem outputs // {
    lib = import ./lib.nix {
      inherit (nixpkgs) lib;
      flakegen-lib = self.lib;
    };
  };
}
