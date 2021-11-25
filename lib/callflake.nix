{ lib, self'lib }: with lib; let
  inherit (self'lib) makeContext callPackageCustomized keepAttrs buildConfigWith supportedSystems;
  inherit (lib) systems;
in {
  callFlake = {
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
    extraArgs = removeAttrs args (buildAttrNames ++ [
      "inputs" "lib" "builders" "systems" "config"
    ]);
    callWith = context: targetName: target: callPackageCustomized {
      inherit context target targetName;
    };
    callWithSystem = name: system: attrs: callWith (staticContextForSystem system) name attrs;
    callWithSystems = name: attrs: genAttrs systems (flip (callWithSystem name) attrs);
    staticContext = buildConfig: makeContext {
      inherit inputs buildConfig;
    };
    buildConfigForSystem = system: buildConfigWith { inherit system; };
    staticContextForSystem = system: staticContext (buildConfigForSystem system);
    buildAttrs = keepAttrs args buildAttrNames;
    staticBuildAttrs = mapAttrs callWithSystems buildAttrs;
    flakes = {
      inherit systems;
      config = config // {
      };
      import = {
        buildConfig
      #, inputs
      }: let
        context = makeContext {
          inherit inputs buildConfig;
        };
      in mapAttrs (callWith context) (buildAttrs // keepAttrs args [ "builders" ]) // {
        inherit flakes;
        inherit (inputs.self) lib;
      };
    };
    staticAttrs = {
      inherit flakes;
      ${if args ? lib then "lib" else null} = callPackageCustomized {
        targetName = "lib";
        target = lib;
        context = makeContext {
          inherit inputs;
          buildConfig = null;
        };
      };
      ${if args ? builders then "builders" else null} = callPackageCustomized {
        targetName = "builders";
        target = builders;
        context = makeContext {
          inherit inputs;
          buildConfig = null;
        };
      };
    };
  in staticBuildAttrs // staticAttrs;
}
