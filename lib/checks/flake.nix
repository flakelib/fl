{
  inputs = {
    nixpkgs.url = "nixpkgs";
    std.url = "flakes-std";
    flakeslib = {
      url = "../";
      inputs = {
        std.follows = "std";
      };
    };
    flakegen = {
      url = "../../flakegen";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flakeslib.follows = "flakeslib";
      };
    };
  };
  outputs = { flakeslib, ... }@inputs: flakeslib {
    inherit inputs;
    checks = import ./checks.nix;
    packages = import ./packages.nix;
  };
}
