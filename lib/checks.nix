{ hello, builders'checkAssert, builders'checkCommand, lib'mainProgram }: let
  # TODO: replace "hello" with something not in nixpkgs
in {
  mainProgramDrv = builders'checkAssert {
    name = "mainProgram-drv";
    cond = lib'mainProgram hello == "${hello}/bin/hello";
  };
  mainProgramPath = builders'checkAssert {
    name = "mainProgram-path";
    cond = lib'mainProgram hello.outPath == "${hello}/bin/hello";
  };
  mainProgram = builders'checkCommand {
    name = "mainProgram-check";
    command = "[[ $(${lib'mainProgram hello} -g hihi) = hihi ]]";
  };
}
