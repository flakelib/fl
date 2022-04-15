{ self, std }: let
  inherit (std.lib) flip set;
  inherit (self.lib) supportedSystems;
  inherit (self.lib.resolver) Context;
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
  callWith = context: targetName: target: Context.callPackageCustomized {
    inherit context target targetName;
  };
  callWithSystem = name: system: attrs: callWith (staticContextForSystem system) name attrs;
  callWithSystems = name: attrs: set.gen systems (flip (callWithSystem name) attrs);
  staticContext = buildConfig: Context.new { inherit inputs buildConfig; };
  buildConfigForSystem = system: Context.BuildConfig.new { inherit system; };
  staticContextForSystem = system: staticContext (buildConfigForSystem system);
  buildAttrs = set.retain (buildAttrNames ++ [ "builders" ]) args;
  staticBuildAttrs = set.map callWithSystems buildAttrs;
  staticBuildAttrs'filtered = set.map (name: systems: let
    isAvailable = drv: let
      available = builtins.tryEval (drv.meta.available or true == true);
    in !available.success || available.value;
    mapSys = system: packages: set.filter (_: isAvailable) packages;
  in set.map mapSys systems) staticBuildAttrs;
  flakes = {
    inherit systems;
    config = config // {
    };
    import = {
      buildConfig
    #, inputs
    }: let
      context = Context.new { inherit inputs buildConfig; };
    in set.map (callWith context) (buildAttrs // set.retain [ "builders" ] args) // {
      inherit flakes context;
      inherit (inputs.self) lib;
    };
    impure = inputs.self.flakes.import {
      buildConfig = Context.BuildConfig.new { system = builtins.currentSystem; };
    };
    outputs = staticBuildAttrs // staticAttrs;
  };
  staticAttrs = {
    inherit flakes;
    ${if args ? lib then "lib" else null} = Context.callPackageCustomized {
      targetName = "lib";
      target = lib;
      context = Context.new { inherit inputs; };
    };
    ${if args ? builders then "builders" else null} = Context.callPackageCustomized {
      targetName = "builders";
      target = builders;
      context = Context.new { inherit inputs; };
    };
  };
in set.without [ "builders" ] staticBuildAttrs'filtered // staticAttrs
