{ hello, checkAssert, checkCommand, std'lib }: let
  inherit (std'lib.drv) mainProgram;
in {
  mainProgram = checkCommand {
    name = "mainProgram-check";
    command = "[[ $(${mainProgram hello} -g hihi) = hihi ]]";
  };
}
