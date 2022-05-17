{ self, std }: let
  inherit (std.lib) Set List;
  inherit (self.lib)
    BuildConfig System
    Inputs FlakeInput
    CallFlake Context;
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
, defaultTemplate ? null
, systems ? System.Supported.tier2
, config ? { }
}@args: let
  call = CallFlake.new {
    inherit inputs config;
    buildConfigs = if builtins.isList systems
      then Set.fromList (List.map (system: let
        bc = BuildConfig system;
      in { _0 = BuildConfig.attrName bc; _1 = bc; }) systems)
      else Set.map (_: BuildConfig) systems;
    args = Set.without [ "systems" "config" "inputs" ] args;
  };
in CallFlake.filteredOutputs call
