{
  inputs = {
    nixpkgs.url = "nixpkgs"; # TODO: replace with nixlib if needed
  };
  outputs = { self, ... }@inputs: {
    lib = import ./lib.nix {
      self'lib = self.lib;
    };
  };
}
