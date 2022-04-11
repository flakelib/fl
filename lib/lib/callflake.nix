{ self, resolver, std }: let
  inherit (std.lib) flip set;
  inherit (self.lib) supportedSystems;
  rctx = resolver.lib.context;
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
  callWith = context: targetName: target: rctx.callPackageCustomized {
    inherit context target targetName;
  };
  callWithSystem = name: system: attrs: callWith (staticContextForSystem system) name attrs;
  callWithSystems = name: attrs: set.gen systems (flip (callWithSystem name) attrs);
  staticContext = buildConfig: rctx.new { inherit inputs buildConfig; };
  buildConfigForSystem = system: rctx.buildConfig.new { inherit system; };
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
      context = rctx.new { inherit inputs buildConfig; };
    in set.map (callWith context) (buildAttrs // set.retain [ "builders" ] args) // {
      inherit flakes context;
      inherit (inputs.self) lib;
    };
    impure = inputs.self.flakes.import {
      buildConfig = rctx.buildConfig.new { system = builtins.currentSystem; };
    };
  };
  staticAttrs = {
    inherit flakes;
    ${if args ? lib then "lib" else null} = rctx.callPackageCustomized {
      targetName = "lib";
      target = lib;
      context = rctx.new { inherit inputs; };
    };
    ${if args ? builders then "builders" else null} = rctx.callPackageCustomized {
      targetName = "builders";
      target = builders;
      context = rctx.new { inherit inputs; };
    };
  };
in staticBuildAttrs // staticAttrs
