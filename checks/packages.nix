{
  systems = { lib, nix-check'build, coreutils, shellCommand }: shellCommand {
    name = "systems.nix";
    command = "$builder $genSystems > $out";
    arg'asFile = true;
    genSystems = ./gen-systems.sh;
    PATH = lib.makeBinPath [ coreutils nix-check'build ];
  };
}
