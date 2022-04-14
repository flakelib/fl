{ systems, hello, checkCommand, std'lib }: let
  inherit (std'lib.drv) mainProgram;
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
