{ self'lib, pkgs }: let
in {
  assertions = {
    mainProgram = mainProgram pkgs.hello == "${pkgs.hello}/bin/hello";
    mainProgramPath = mainProgram pkgs.hello.outPath == "${pkgs.hello}/bin/hello";
  };
  mainProgram = checkCommand {
    command = "${mainProgram pkgs.hello} -g hihi";
  };
}
