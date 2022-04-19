{ self, std }: let
  inherit (std.lib) flip set list bool function types;
  inherit (self.lib)
    BuildConfig System
    Inputs FlakeInput
    CallFlake Context
    supportedSystems;
in {
  inputs
, packages ? null, defaultPackage ? null, legacyPackages ? null
, checks ? null, hydraJobs ? null
, apps ? null, defaultApp ? null
, devShells ? null, devShell ? null
, lib ? null, builders ? null
, overlays ? null, overlay ? null
, nixosModules ? null, nixosModule ? null
, nixosConfigurations ? null
, defaultTemplate ? null
, systems ? supportedSystems.tier2
, config ? { }
}@args: let
  inputs = Inputs.withFlakeInputs args.inputs;
  call = CallFlake.new {
    inherit inputs config;
    buildConfigs = list.map BuildConfig systems;
    args = set.without [ "systems" "config" "inputs" ] args;
  };
in CallFlake.filteredOutputs call
