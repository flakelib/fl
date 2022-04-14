{ systems, hello, checkCommand, std2'lib }: let
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
}
