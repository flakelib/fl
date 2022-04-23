{ systems, hello, checkCommand, callPackageSet, std2'lib }: let
  inherit (std2'lib.drv) mainProgram;
in {
  mainProgram = checkCommand {
    name = "mainProgram-check";
    command = "[[ $(${mainProgram hello} -g hihi) = hihi ]]";
  };
  systemsUpToDate = checkCommand {
    name = "systems.nix-upToDate-check";
    command = "[[ $(cat ${systems}) = $(cat ${../lib/systems.nix}) ]]";
  };
} // callPackageSet {
  broken-package = { broken-package }: checkCommand {
    name = "broken-package-check";
    command = "[[ -n ${broken-package.name} ]]";
  };
  broken-package-filtered = { checkAssert, buildConfig, inputs, flakelib'lib }: checkAssert {
    name = "broken-package-filtered-check";
    cond = ! inputs.self.packages.${flakelib'lib.BuildConfig.attrName buildConfig} ? broken-package;
  };
  unsupported-system = { stdenvNoCC }: stdenvNoCC.mkDerivation {
    name = "broken";
    meta.platforms = [ ];
  };
} { }
