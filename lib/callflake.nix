{ std, resolver, self'lib }: let
  inherit (std) flip set;
  inherit (self'lib) supportedSystems;
in {
  inputs
, packages ? null, defaultPackage ? null, legacyPackages ? null
, checks ? null
, apps ? null, defaultApp ? null
, devShells ? null, devShell ? null
, lib ? null, builders ? null
, systems ? supportedSystems.tier2
, config ? { }
, ...
}@args: let
  buildAttrNames = [ "packages" "defaultPackage" "legacyPackages" "checks" "apps" "defaultApp" "devShells" "devShell" ];
  extraArgs = set.without (buildAttrNames ++ [
    "inputs" "lib" "builders" "systems" "config"
  ]) args;
  callWith = context: targetName: target: resolver.context.callPackageCustomized {
    inherit context target targetName;
  };
  callWithSystem = name: system: attrs: callWith (staticContextForSystem system) name attrs;
  callWithSystems = name: attrs: set.gen systems (flip (callWithSystem name) attrs);
  staticContext = buildConfig: resolver.context.new inputs buildConfig;
  buildConfigForSystem = system: resolver.context.buildConfig.new { inherit system; };
  staticContextForSystem = system: staticContext (buildConfigForSystem system);
  buildAttrs = set.retain buildAttrNames args;
  staticBuildAttrs = set.map callWithSystems buildAttrs;
  flakes = {
    inherit systems;
    config = config // {
    };
    import = {
      buildConfig
    #, inputs
    }: let
      context = resolver.context.new inputs buildConfig;
    in set.map (callWith context) (buildAttrs // set.retain [ "builders" ] args) // {
      inherit flakes context;
      inherit (inputs.self) lib;
    };
    impure = inputs.self.flakes.import {
      buildConfig = resolver.context.buildConfig.new { system = builtins.currentSystem; };
    };
  };
  staticAttrs = {
    inherit flakes;
    ${if args ? lib then "lib" else null} = resolver.context.callPackageCustomized {
      targetName = "lib";
      target = lib;
      context = resolver.context.new inputs null;
    };
    ${if args ? builders then "builders" else null} = resolver.context.callPackageCustomized {
      targetName = "builders";
      target = builders;
      context = resolver.context.new inputs null;
    };
  };
in staticBuildAttrs // staticAttrs
