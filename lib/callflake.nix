{ self }: let
  inherit (self.lib.Std) BuildConfig System Set List;
  inherit (self.lib) Fl;

  argKeys = [ "systems" "config" "outputs" "inputs" ];
  defaultKeys = Set.keys defaultMap;
  defaultMap = {
    defaultPackage = "packages";
    defaultApp = "apps";
    defaultBundler = "bundlers";
    defaultTemplate = "templates";
    devShell = "devShells";
    overlay = "overlays";
    nixosModule = "nixosModules";
  };
  defaultArgs = args: Set.fromList (Set.values (Set.mapIntersection (name: outputAttr: default: {
    _0 = outputAttr;
    _1 = { inherit default; };
  }) defaultMap args));
  outputArgs = args: Set.map (_: value: {
    inherit value;
  }) (Set.without (argKeys ++ defaultKeys) args);
in {
  inputs
, packages ? null, defaultPackage ? null, legacyPackages ? null
, checks ? null, hydraJobs ? null
, apps ? null, defaultApp ? null
, bundlers ? null, defaultBundler ? null
, devShells ? null, devShell ? null
, lib ? null, builders ? null
, overlays ? null, overlay ? null
, nixosModules ? null, nixosModule ? null
, nixosConfigurations ? null
, templates ? null, defaultTemplate ? null
, systems ? System.Supported.tier2
, config ? { }
, outputs ? { }
}@args: let
  allOutputs = Set.mapZip (_: values: List.foldr Set.update { } values) [
    (defaultArgs args)
    (outputArgs args)
    outputs
  ];
  desc = Fl.Desc.New {
    inherit inputs config;
    buildConfigs = if builtins.isList systems
      then Set.fromList (List.map (system: let
        bc = BuildConfig system;
      in { _0 = BuildConfig.attrName bc; _1 = bc; }) systems)
      else Set.map (_: BuildConfig) systems;
    args = Set.without argKeys args;
    outputs = Set.map (name: output: Fl.Desc.Output.New ({
      inherit name;
    } // output)) allOutputs;
  };
in Fl.Desc.make desc
