{ self }: let
  inherit (self.lib.Std) System Set Opt;
  inherit (self.lib) Fl BuildConfig;
  inherit (Fl) Defaults;
in {
  FlakeImporters = {
    nixpkgs = { outputs, buildConfig, ... }: {
      inherit (outputs) lib;
      legacyPackages = import (outputs.outPath + "/default.nix") rec {
        localSystem = System.serialize (BuildConfig.localSystem buildConfig);
        crossSystem = Opt.match (BuildConfig.crossSystem buildConfig) {
          just = System.serialize;
          nothing = localSystem;
        };
        # TODO: populate from inputConfig in some way
        config = {
          checkMetaRecursively = true;
        };
        overlays = [ ];
        crossOverlays = [ ];
      };
    };
  };

  InputConfigs = Set.map (name: config: Fl.Config.Input.New { inherit name config; }) {
    nixpkgs = {
      import.${Fl.ImportMethod.DefaultImport} = Defaults.FlakeImporters.nixpkgs;
    };
  };
}
