{
  systems = { nix-check'build, coreutils'build, shellCommand }: shellCommand {
    name = "systems.nix";
    command = "$builder $genSystems > $out";
    arg'asFile = true;
    genSystems = ./gen-systems.sh;
    PATH = [ nix-check'build coreutils'build ];
  };
  broken-package = { stdenvNoCC }: stdenvNoCC.mkDerivation {
    name = "broken";
    meta.platforms = [ ];
  };
}
