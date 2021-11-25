{ lib, self'lib }: with lib; let
  inherit (self'lib) makeContext callPackageCustomized keepAttrs buildConfigWith;
  inherit (lib) systems;
in {
  callFlake = {
    inputs
  , packages ? null
  , legacyPackages ? null
  , checks ? null
  , apps ? null
  , lib ? null
  , supportedSystems ? "supported"
  , config ? { }
  , ...
  }@args: let
    flakeSystems =
      if supportedSystems == "supported" then systems.supported.hydra
      else if isString supportedSystems
      then systems.doubles.${supportedSystems}
      else supportedSystems;
    callWith = context: targetName: target: callPackageCustomized {
      inherit context target targetName;
    };
    callWithSystem = name: system: attrs: callWith (staticContextForSystem system) name attrs;
    callWithSystems = name: attrs: genAttrs flakeSystems (flip (callWithSystem name) attrs);
    staticContext = buildConfig: makeContext {
      inherit inputs buildConfig;
    };
    buildConfigForSystem = system: buildConfigWith { inherit system; };
    staticContextForSystem = system: staticContext (buildConfigForSystem system);
    buildAttrs = keepAttrs args [ "packages" "legacyPackages" "checks" "apps" ];
    staticBuildAttrs = mapAttrs callWithSystems buildAttrs;
    flakes = {
      systems = flakeSystems;
      config = config // {
      };
      import = {
        buildConfig
      #, inputs
      }: let
        context = makeContext {
          inherit inputs buildConfig;
        };
      in mapAttrs (callWith context) buildAttrs // {
        inherit flakes;
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
    };
  in staticBuildAttrs // staticAttrs;
}
