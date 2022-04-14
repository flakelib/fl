{ checkAssert, callPackage }: let
in {
  recursive-callPackage = callPackage ({ lib }: checkAssert {
    name = "recursive-callPackage";
    cond = lib ? callFlake;
  }) { };
}
