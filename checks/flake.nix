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
  outputs = { flakelib, ... }@inputs: flakelib {
    inherit inputs;
    checks = import ./checks.nix;
    packages = import ./packages.nix;
  };
}
