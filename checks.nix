{ lib, self'lib, checkAssert, callPackage, callPackageSet }: let
in lib.Nix.SeqDeep (lib.Set.without [ "Std" ] self'lib) {
  recursive-callPackage = callPackage ({ lib }: checkAssert {
    name = "recursive-callPackage";
    cond = lib ? flakelib.callFlake;
  }) { };
} // lib.Fn.flip callPackageSet { } {
  inputName-scope = { std'lib'Ty, self'pkgs'checkAssert }: checkAssert {
    name = "inputName-scope";
    cond = std'lib'Ty.function.check self'pkgs'checkAssert;
  };
  optional-arg = { checkAssert, nonexistent ? 1 }: checkAssert {
    name = "optional-arg";
    cond = nonexistent == 1;
  };
  fallback-arg = lib.Fn.toFunctor ({ checkAssert, nonexistent }: checkAssert {
    name = "fallback-arg";
    cond = nonexistent == 1;
  }) // {
    fl'config.args.nonexistent.fallback = 1;
  };
  fallback-optional-arg = lib.Fn.toFunctor ({ checkAssert, nonexistent ? 1 }: checkAssert {
    name = "fallback-optional-arg";
    cond = nonexistent == 2;
  }) // {
    fl'config.args.nonexistent.fallback = 2;
  };
}
