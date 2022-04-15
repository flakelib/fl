{ self, std }: let
  inherit (std.lib) types set function;
  inherit (self.lib.resolver) flake Context;
in {
  # importInput :: context -> input -> args -> resolved
  importInput = context: input: let
    hasImport = builtins.pathExists "${toString input}/default.nix";
    imported = import input;
    fallback =
      if !hasImport then {}: {}
      else if types.function.check imported then imported
      else {}: imported;
    importer = input.flakes.import or fallback;
    scope = Context.importScope context;
  in function.wrapScoped scope importer;

  # loadInput :: context -> input -> args -> resolved
  loadInput = context: input: args: let
    inherit (context.buildConfig.localSystem) system;
    isBuild = context.buildConfig != null;
    isNative = isBuild && Context.BuildConfig.isNative context.buildConfig;
    useNative = isNative && args == { };
    ioutputs = input.flake.outputs or input;
    outputs = { # TODO: do not use `outputs` since it already exists? or idk :<
      packages = ioutputs.packages.${system} or { };
      legacyPackages = ioutputs.legacyPackages.${system} or { };
      checks = ioutputs.checks.${system} or { };
      apps = ioutputs.apps.${system} or { };
    };
    imported = flake.importInput context input args;
    nativePackages = outputs.legacyPackages // outputs.packages;
  in input // {
    inherit input imported;
    inherit (context) buildConfig;
    builders = if input ? flakes.import
      then imported.builders or input.builders or { }
      else input.builders or { };
  } // set.optional isNative {
    inherit system outputs;
  } // set.optional isBuild {
    packages = if useNative then nativePackages else imported;
  };
}
