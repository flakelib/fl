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
  optional-arg = { checkAssert, nonexistent ? 1 }: checkAssert {
    name = "optional-arg";
    cond = builtins.trace nonexistent nonexistent == 1;
  };
  fallback-arg = lib.function.toFunctor ({ checkAssert, nonexistent }: checkAssert {
    name = "fallback-arg";
    cond = nonexistent == 1;
  }) // {
    fl'config.args.nonexistent.fallback = 1;
  };
  fallback-optional-arg = lib.function.toFunctor ({ checkAssert, nonexistent ? 1 }: checkAssert {
    name = "fallback-optional-arg";
    cond = nonexistent == 2;
  }) // {
    fl'config.args.nonexistent.fallback = 2;
  };
}
