{
  systems = { nix-check'build, shellCommand }: shellCommand {
    name = "systems.nix";
    command = "$builder $genSystems > $out";
    arg'asFile = true;
    genSystems = ./gen-systems.sh;
    PATH = "${nix-check'build}/bin";
  };
}
