{ lib, flakegen-lib }: let
in {
  modules = {
    flake = ./module.nix;
  };

  mkFlake = config: let
    eval = lib.evalModules {
      modules = [
        flakegen-lib.modules.flake
        config
      ];
    };
  in eval.config.out.attrs // {
    inherit (eval) config options;
  };
}
