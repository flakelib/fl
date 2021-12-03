{
  inputs = {
    nixpkgs.url = "nixpkgs";
    std.url = "flakes-std";
    flakes = {
      url = "../";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        std.follows = "std";
      };
    };
  };
  outputs = { flakes, ... }@inputs: flakes {
    inherit inputs;
    checks = import ./checks.nix;
  };
}
