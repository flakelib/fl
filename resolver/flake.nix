{
  inputs = {
    std.url = "flakes-std";
  };
  outputs = { self, std, ... }@inputs: let
  in {
    flakes.config.aliases = [ "res" ];
    lib = import ./lib.nix {
      inherit self;
      std = std.lib;
    };
  };
}
