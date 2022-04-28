{
  systems = { buildPackages, coreutils'build, shellCommand }: shellCommand {
    name = "systems.nix";
    command = "$builder $genSystems > $out";
    arg'asFile = true;
    genSystems = ./gen-systems.sh;
    PATH = [ buildPackages.nix-check coreutils'build ];
  };
  broken-package = { stdenvNoCC }: stdenvNoCC.mkDerivation {
    name = "broken";
    meta.platforms = [ ];
  };
  merge-override-test = { runCommand }: runCommand "override-test" { } "touch $out";
}
