{ self, std }: let
  inherit (std.lib) Ty Rec List Set Opt;
  inherit (self.lib) Fl BuildConfig;
  inherit (Fl) Desc Context;
  Outputs = std.lib.Flake.Outputs // self.lib.Flake.Outputs;
in Rec.Def {
  name = "fl:Fl.Desc";
  Self = Desc;
  fields = {
    inputs.type = Ty.attrsOf (Ty.flakeInput);
    config.type = Fl.Config.TypeId.ty;
    buildConfigs.type = Ty.attrsOf BuildConfig.TypeId.ty;
    args.type = Ty.attrs;
  };
  show = desc: let
    name = Opt.match (Fl.Config.name (Desc.flConfig desc)) {
      just = name: "(${name})";
      nothing = "";
    };
  in "Fl.Desc" + name;

  fn.flOutput = desc: {
    inherit (desc) config args;
    systems = Set.map (_: BuildConfig.serialize) desc.buildConfigs;
    import = { buildConfig }: (Desc.self desc) // (Context.outputs (Context.byBuildConfig (Desc.staticContext desc) buildConfig));
    impure = (Desc.flOutput desc).import {
      buildConfig = BuildConfig.Impure;
    };
    outputs = Desc.outputs desc;
    globals = Context.globalScope (Desc.staticContext desc);
  };

  fn.flConfig = desc: Fl.Config.New desc.config;
  fn.args = desc: desc.args;
  fn.staticContext = desc: Context.New { inherit desc; };
  fn.nativeContexts = desc: Set.map (_: Context.byBuildConfig (Desc.staticContext desc)) desc.buildConfigs;
  fn.contextOutputs = desc: Set.map (_: Context.outputs) (Desc.nativeContexts desc);
  fn.staticOutputs = desc: Set.retain Outputs.StaticAttrs (Context.outputs (Desc.staticContext desc));
  fn.filteredNativeOutputs = desc: let
    contextOutputs = Desc.contextOutputs desc;
    packageAttrs = Set.retain (Outputs.NativeAttrs ++ Outputs.FlNativePackageSetAttrs) desc.args;
    filterOutput = name: output: let
      available = builtins.tryEval (output.meta.available or true);
    in available.value || !available.success;
    filterOutputs = name: outputs: rec {
      # TODO: how to handle apps and devShells?
      checks = Set.filter filterOutput outputs;
      packages = checks; # TODO: consider Set.map'ing anything broken into an unbuildable derivation instead
      legacyPackages = builtins.trace "TODO:Desc.filteredNativeOutputs/filterOutputs/legacyPackages" packages;
    }.${name} or outputs;
  in Set.map (name: _: Set.map (system: outputs: filterOutputs name outputs.${name}) contextOutputs) packageAttrs;
  fn.filteredOutputs = desc: let
    filteredNativeOutputs = Desc.filteredNativeOutputs desc;
  in Desc.staticOutputs desc // filteredNativeOutputs // {
    flakes = Desc.flOutput desc // Set.retain Outputs.FlNativePackageSetAttrs filteredNativeOutputs;
  };
  fn.nativeOutputs = desc: let
    contextOutputs = Desc.contextOutputs desc;
    packageAttrs = Set.retain (Outputs.NativeAttrs ++ Outputs.FlNativePackageSetAttrs) desc.args;
  in Set.map (name: _: Set.map (system: outputs: outputs.${name}) contextOutputs) packageAttrs;
  fn.outputs = desc: let
    nativeOutputs = Desc.nativeOutputs desc;
  in Desc.staticOutputs desc // nativeOutputs // {
    flakes = Desc.flOutput desc // Set.retain Outputs.FlNativePackageSetAttrs nativeOutputs;
  };

  fn.self = desc: desc.inputs.self or (throw "who am i?");
  fn.inputConfigs = desc: let
    # TODO: consider whether `self` gets special treatment here or not
    inputConfigs = Fl.Config.inputConfigs (Desc.flConfig desc);
  in Set.map (name: _: Fl.Config.Input.Default name) desc.inputs // inputConfigs;

  fn.filteredInputs = desc: let
    inputConfigs = Desc.inputConfigs desc;
  in Set.filter (name: _: Fl.Type.isInput (Fl.Config.Input.flType inputConfigs.${name})) desc.inputs;

  # canonicalizeInputName :: Desc -> Optional string
  fn.canonicalizeInputName = desc: name: Opt.match (Set.lookup name desc.inputs) {
    just = _: Opt.just name;
    nothing = Set.lookup name (Desc.inputAliases desc);
  };

  # inputAliases :: Desc -> { string => InputName }
  fn.inputAliases = desc: let
    inputConfigs = Desc.inputConfigs desc;
    aliasPairs = name: inputConfig: List.map (alias: { _0 = alias; _1 = name; }) (Fl.Config.Input.aliases inputConfig);
    selfAlias = Opt.match (Fl.Config.name (Desc.flConfig desc)) {
      just = name: List.One { _0 = name; _1 = "self"; };
      nothing = List.Nil;
    };
  in Set.fromList (List.concat (Set.mapToList aliasPairs inputConfigs) ++ selfAlias);

  # allInputNames :: Desc -> [InputName]
  fn.allInputNames = desc: Desc.orderedInputNames desc ++ Set.keys (Desc.inputAliases desc);

  # orderedInputNames :: Desc -> [InputName]
  fn.orderedInputNames = desc:
    List.One "self" ++ Set.keys (Set.without [ "self" ] (Desc.filteredInputs desc));
} // {
  New = {
    inputs
  , buildConfigs
  , config
  , args
  }@desc: Desc.TypeId.new desc;
}
