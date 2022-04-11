{ self, std }: let
  inherit (std.lib) types set function;
  inherit (self.lib) flake context;
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
    scope = context.importScope context;
  in function.wrapScoped scope importer;

  # loadInput :: context -> input -> args -> resolved
  loadInput = context: input: args: let
    inherit (context.buildConfig.localSystem) system;
    isBuild = context.buildConfig != null;
    isNative = isBuild && context.buildConfig.isNative context.buildConfig;
    useNative = isNative && args == { };
    outputs = { # TODO: do not use `outputs` since it already exists? or idk :<
      packages = input.packages.${system} or { };
      legacyPackages = input.legacyPackages.${system} or { };
      checks = input.checks.${system} or { };
      apps = input.apps.${system} or { };
    };
    imported = flake.importInput context input args;
    nativePackages = outputs.legacyPackages // outputs.packages;
  in input // {
    inherit input imported;
    inherit (context) buildConfig;
    builders = imported.builders or input.builders or { };
  } // set.optional isNative {
    inherit system outputs;
  } // set.optional isBuild {
    packages = if useNative then nativePackages else imported;
  };
}
