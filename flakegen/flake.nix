{
  inputs = {
    nixpkgs.url = "nixpkgs";
    flakeslib.url = "../lib";
  };
  outputs = { flakeslib, ... }@inputs: flakeslib {
    inherit inputs;
    builders = import ./builders.nix;
    checks = import ./checks.nix;
    lib = import ./lib.nix;
  };
}
