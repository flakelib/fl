{ self }: let
  inherit (self.lib.Std)
    Flake BuildConfig
    Ty Rec Enum List Set Opt Fn;
  inherit (Flake) Outputs;
  inherit (self.lib) Fl;
  inherit (Fl) Desc Context InputOutputs;
  inherit (Context) ScopedContext;
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
    inherit (desc) config;
    args = desc.args // {
      inherit (desc) outputs;
    };
    systems = Set.map (_: BuildConfig.serialize) desc.buildConfigs;
    import = { buildConfig }: Desc.contextualOutputs desc (Context.byBuildConfig (Desc.staticContext desc) buildConfig);
    impure = (Desc.flOutput desc).import {
      buildConfig = BuildConfig.Impure;
    };
    outputs = Desc.outputs desc;
    globals = Context.globalScope (Desc.staticContext desc);
  };

  fn.flConfig = desc: Fl.Config.New desc.config;

  fn.staticContext.fn = desc: Context.New { inherit desc; };
  fn.staticContext.memoize = true;

  fn.contextualInputOutputs.fn = desc: context: Set.map (name: outputs: InputOutputs.Import {
    inherit outputs;
    inherit (context) buildConfig;
    inputConfig = (Desc.inputConfigs desc).${name};
  }) (Desc.filteredInputs desc) // {
    self = InputOutputs.New {
      outputsData = Desc.contextualOutputs desc context;
      inputConfig = (Desc.inputConfigs desc).self;
      flConfig = Desc.flConfig desc;
    };
  };

  fn.nativeContexts.fn = desc: Set.map (_: Context.byBuildConfig (Desc.staticContext desc)) desc.buildConfigs;
  fn.nativeContexts.memoize = true;

  fn.outputs.fn = desc: Set.map (_: Fn.flip Desc.Output.resolved desc) desc.outputs;
  fn.outputs.memoize = true;

  fn.cleanOutputs.fn = desc: Set.map (name: Desc.Output.clean desc.outputs.${name}) (Desc.outputs desc);
  fn.cleanOutputs.memoize = true;

  fn.make = desc: Desc.cleanOutputs desc // {
    ${Fl.Data.OutputName} = Desc.flOutput desc;
  };

  fn.contextualOutputs = desc: let
    contextual = Set.filter (_: Desc.Output.isContextual) desc.outputs;
  in context: desc.inputs.self or { } // Desc.outputs desc // Set.map (_: Fn.flip Desc.Output.contextual context) contextual;

  fn.inputConfigs.fn = desc: let
    # TODO: consider whether `self` gets special treatment here or not
    inputConfigs = Fl.Config.inputConfigs (Desc.flConfig desc);
  in Set.map (name: _: Fl.Config.Input.Default name) desc.inputs // inputConfigs;
  fn.inputConfigs.memoize = true;

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
  , outputs
  }@desc: Desc.TypeId.new desc;

  Output = let
    inherit (Desc) Output;
    inherit (Output) Type;
    namedTypes = rec {
      legacyPackages = Type.LegacyPackages;
      packages = Type.Packages;
      checks = Type.Checks;
      hydraJobs = Type.HydraJobs;
      apps = Type.Apps;
      bundlers = Type.NativeOf (Type.AttrsOf Type.Bundler);
      devShells = Type.DevShells;
      lib = Type.Lib;
      builders = Type.FlBuilders;
      nixosModules = Type.NixosModules;
      nixosConfigurations = Type.NixosConfigurations;
      templates = Type.Templates;
    };
    tryImport = v: if Ty.path.check v then import v else v;
  in Rec.Def {
    name = "fl:Fl.Desc.Output";
    Self = Output;
    fields = {
      name.type = Ty.string;
      value.type = Ty.any;
      default = {
        type = Ty.nullOr Ty.any;
        default = null;
      };
      type.type = Type.TypeId.ty;
    };

    fn.scoped = output: context: Context.scopeFor context {
      path = List.One output.name;
    };

    fn.isContextual = output: Type.isContextual output.type;

    fn.contextual = output: context: let
      scoped = Output.scoped output context;
    in output.type.loader {
      inherit output scoped;
    };

    fn.resolved = output: desc: let
      scoped = Output.scoped output (Desc.staticContext desc);
    in output.type.resolver {
      inherit output scoped;
    };

    fn.clean = output: resolved: output.type.cleaner {
      inherit output resolved;
    };

    fn.valueAttr = output: name: value: output // {
      name = "${output.name}.${name}";
      inherit value;
      type = Type.atAttr output.type name;
    };

    fn.setType = output: type: output // {
      inherit type;
    };

    fn.callOverrides = output: { }; # TODO
  } // {
    New = {
      name
    , value
    , default ? null
    , type ? Type.ForName name
    }: Output.TypeId.new {
      inherit name value default type;
    };

    Type = Rec.Def {
      name = "fl:Fl.Desc.Output.Type";
      Self = Type;
      fields = {
        loader.type = Ty.function;
        resolver.type = Ty.function;
        cleaner.type = Ty.function;
        contextual.type = Ty.bool;
      };
      fn.atAttr = type: name: type.attrTypes.${name} or type.attrTypes."" or type; # TODO
      fn.isContextual = type: type.contextual;
    } // {
      New = {
        loader ? { output, scoped }: output.value
      , resolver ? { output, scoped }: loader { inherit output scoped; }
      , cleaner ? { output, resolved }: resolved
      , attrTypes ? { }
      , contextual ? false
      }: Type.TypeId.new {
        inherit loader resolver cleaner attrTypes contextual;
      };

      NativeOf = type: Type.New {
        contextual = true;
        loader = {
          output
        , scoped
        }: type.loader {
          inherit scoped;
          output = Output.setType output type;
        };

        resolver = {
          output
        , scoped
        }: Set.map (key: context: type.resolver {
          output = Output.setType output type;
          scoped = ScopedContext.New {
            inherit (scoped) scope;
            inherit context;
            path = scoped.path ++ [ key ];
          };
        }) (Desc.nativeContexts scoped.context.desc);

        cleaner = {
          output
        , resolved
        }: Set.map (_: resolved: type.cleaner {
          output = Output.setType output type;
          inherit resolved;
        }) resolved;
      };

      AttrsOf = type: Type.New {
        inherit (type) contextual;
        attrTypes."" = type;

        loader = {
          output
        , scoped
        }: let
          value = tryImport output.value;
        in if Ty.function.check value
          then ScopedContext.callFn scoped value (Output.callOverrides output)
          else Set.map (key: value: type.loader {
            scoped = ScopedContext.push scoped key;
            output = Output.valueAttr output key value;
          }) value;

        resolver = {
          output
        , scoped
        }: Set.map (key: value: type.resolver {
          scoped = ScopedContext.push scoped key;
          output = Output.valueAttr output key value;
        }) (output.type.loader { inherit output scoped; });

        cleaner = {
          output
        , resolved
        }: Set.map (_: resolved: type.cleaner {
          inherit output resolved;
        }) resolved;
      };

      Attrs = Type.AttrsOf Type.Any;

      Drvs = Type.AttrsOf Type.Drv // {
        cleaner = let
          filterOutput = name: resolved: let
            available = builtins.tryEval (resolved.meta.available or true);
          in available.value || !available.success;
        in { output, resolved }: Set.filter filterOutput resolved;
      };

      LegacyPackages = Type.NativeOf Type.Attrs; # TODO: filter recursively?

      HydraJobs = Type.AttrsOf (Type.NativeOf Type.Drv) // {
        # TODO: cleaner
      };

      Apps = Type.NativeOf (Type.AttrsOf Type.App);

      Packages = Type.NativeOf Type.Drvs;
      Checks = Type.Packages;
      DevShells = Type.Packages;
      Lib = Type.Attrs;
      FlBuilders = Type.Native (Type.AttrsOf Type.Builder);
      NixosModules = Type.Attrs;
      NixosConfigurations = Type.Attrs;
      Templates = Type.AttrsOf Type.Template;

      Native = Type.NativeOf; # TODO: cleaner should make this contextless?

      Drv = Type.New {
        loader = {
          output
        , scoped
        }: let
          value = tryImport output.value;
        in if Ty.function.check value && ! Ty.drv.check value
          then ScopedContext.callPackage scoped value (Output.callOverrides output)
          else value;
      };

      Any = Type.New { };

      App = Type.New {
        resolver = {
          output
        , scoped
        }: let
          value = output.type.loader { inherit output scoped; };
        in if Ty.drv.check value then Flake.App.ForDrv value else value;
      };
      Bundler = Type.Function;
      Function = Type.Any;

      Builder = Type.Function // {
        loader = {
          output
        , scoped
        }: let
          value = tryImport output.value;
        in ScopedContext.callPackage scoped value (Output.callOverrides output);
      };

      Template = Type.Attrs; # TODO: { path = "<store-path>"; description = ""; }

      ForName = name: namedTypes.${name} or Type.Attrs;
    };
  };
}
