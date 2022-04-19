{ lib, checkAssert, callPackage, callPackageSet }: let
in {
  recursive-callPackage = callPackage ({ lib }: checkAssert {
    name = "recursive-callPackage";
    cond = lib ? flakelib.callFlake;
  }) { };
} // lib.function.flip callPackageSet { } {
  inputName-scope = { std'lib'types, self'pkgs'checkAssert }: checkAssert {
    name = "inputName-scope";
    cond = std'lib'types.function.check self'pkgs'checkAssert;
  };
}
