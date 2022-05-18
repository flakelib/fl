{ self, std }: let
  inherit (std.lib) Ty Rec Str Bool List Set Fn Opt;
  inherit (self.lib)
    QueryScope
    Callable
    CallFlake Context
    BuildConfig System
    FlakeInput InputConfig FlConfig
    InputOutputs;
  inherit (Callable) ArgDesc Offset;
  inherit (Context) ScopedContext;
in Rec.Def {
  name = "fl:Context";
  Self = Context;
  fields = {
    call.type = CallFlake.TypeId.ty;
    buildConfig.type = BuildConfig.TypeId.ty;
    inputOutputs = {
      type = Ty.any;
      private = true;
    };
  };

  fn.byOffset = context: offset: Opt.match (Context.buildConfig context) {
    nothing = context;
    just = buildConfig:
      if Context.isNative context then context
      else Context.New {
        inherit (context) call;
        buildConfig = BuildConfig.byOffset buildConfig offset;
      };
  };

  fn.byBuildConfig = context: buildConfig: Context.New {
    inherit (context) call;
    inherit buildConfig;
  };

  fn.scopeFor = context: args: ScopedContext.New ({
    inherit context;
  } // args);

  fn.callArgsFor = context: path: Set.atOr { } path (FlConfig.callArgs (FlakeInput.flConfig (CallFlake.flConfig context.call)));

  fn.isNative = context: Opt.isJust (Context.buildConfig context) && BuildConfig.isNative context.buildConfig;
  fn.orderedInputOutputs = context: List.map (name:
    Set.get name context.inputOutputs
  ) (CallFlake.orderedInputNames context.call);
  fn.orderedOutputs = context: List.map (io: InputOutputs.outputs io) (Context.orderedInputOutputs context);

  fn.buildConfig = context: Opt.fromNullable context.buildConfig;

  fn.orderedInputNames = context:
    List.One "self" ++ Set.keys (Set.without [ "self" ] context.flakes);

  fn.inputByName = context: inputName: Set.lookup inputName context.flakes;

  fn.globalScope = context: {
    inherit context;
    inherit (context) buildConfig;
    callPackage = Context.callPackage context;
    callPackages = Context.callPackages context;
    callPackageSet = Context.callPackageSet context;
    inputs = CallFlake.flakeInputs context.call;
    outputs = InputOutputs.outputs context.inputOutputs.self;
    pkgs = InputOutputs.MergeScopes (List.map (io: InputOutputs.namespacedPkgs io) (Context.orderedInputOutputs context));
    lib = InputOutputs.MergeScopes (List.map (io: InputOutputs.namespacedLib io) (Context.orderedInputOutputs context));
    buildPackages = (ScopedContext.global (Context.scopeFor (Context.byOffset context Offset.Build) {})).pkgs;
    targetPackages = (ScopedContext.global (Context.scopeFor (Context.byOffset context Offset.Target) {})).pkgs;
  };

  fn.outputs = context: let
    args = CallFlake.args context.call;
    packageSets = Set.retain (FlakeInput.NativePackageSetAttrs ++ FlakeInput.FlNativePackageSetAttrs) args;
    attrOf = name: Bool.toNullable (args ? ${name}) name;
    scoped = Context.scopeFor context {
      inherit outputs;
      scope = QueryScope.Packages;
      path = [ ];
    };
    callPackageAt = attrName: target: ScopedContext.callPackage (
      ScopedContext.push scoped [ attrName (BuildConfig.attrName context.buildConfig) ]
    ) target (Context.callArgsFor context [ attrName ]);
    callPackageSetAt = attrName: target: ScopedContext.callPackageSet (
      ScopedContext.push scoped [ attrName (BuildConfig.attrName context.buildConfig) ]
    ) target (Context.callArgsFor context [ attrName ]);
    mapDefault = defaults: fn: default: if Ty.string.check default
      then defaults.${default} or (throw "TODO: couldn't find default ${default}")
      else fn default;
    staticAttrs = Set.retain FlakeInput.StaticAttrs args // {
      flakes = CallFlake.flOutput context.call;
      ${attrOf "lib"} = ScopedContext.callPackageSet (Context.scopeFor context {
        inherit outputs;
        scope = QueryScope.Lib;
        path = [ "lib" ];
      }) args.lib (Context.callArgsFor context [ "lib" ]);
      ${attrOf "overlay"} = mapDefault outputs.overlays Fn.id args.overlay;
      ${attrOf "nixosModule"} = mapDefault outputs.nixosModules Fn.id args.nixosModule;
      ${attrOf "defaultTemplate"} = mapDefault outputs.templates Fn.id args.defaultTemplate;
      ${attrOf "defaultPackage"} = mapDefault outputs.packages (callPackageAt "defaultPackage") args.defaultPackage;
      ${attrOf "defaultApp"} = mapDefault outputs.apps (callPackageAt "defaultApp") args.defaultApp;
      ${attrOf "devShell"} = mapDefault outputs.devShells (callPackageAt "devShell") args.devShell;
      # TODO: builders
    };
    nativeAttrs = Set.map callPackageSetAt packageSets;
    outputs = staticAttrs // nativeAttrs;
  in outputs;

  show = context: let
    self = CallFlake.describe context.call;
    bc = Opt.match (Context.buildConfig context) {
      just = bc: "(${BuildConfig.show bc})";
      nothing = "";
    };
  in "${self}${bc}";
} // {
  # New :: set -> Context { buildConfig :: BuildConfig?, call :: CallFlake }
  New = {
    call
  , buildConfig ? null
  }: let
    inputConfigs = CallFlake.inputConfigs call;
    context = {
      inherit call buildConfig;
      inputOutputs = Set.map (name: flakeInput: InputOutputs.new rec {
        inherit context flakeInput;
        inputConfig = inputConfigs.${name};
        importMethod = Opt.toNullable (InputConfig.importMethod inputConfig);
      }) (CallFlake.filteredInputs call);
    };
  in Context.TypeId.new context;

  ScopedContext = Rec.Def {
    name = "fl:Context.ScopedContext";
    Self = ScopedContext;
    fields = {
      context.type = Context.TypeId.ty;
      scope = {
        type = QueryScope.TypeId.ty;
        default = QueryScope.Default;
      };
      path = {
        type = Ty.listOf Ty.string;
        default = [ ];
      };
      outputs = {
        type = Ty.nullOr Ty.any;
        default = null;
      };
    };

    fn.push = scoped: path: scoped // {
      path = scoped.path ++ (List.From path);
    };

    fn.byOffset = scoped: offset: scoped // {
      # TODO: use new
      context = Context.byOffset scoped.context offset;
    };

    fn.global = scoped: Context.globalScope scoped.context // {
      callPackage = ScopedContext.callPackage scoped;
      callPackages = ScopedContext.callPackages scoped;
      callPackageSet = ScopedContext.callPackageSet scoped;
    };

    fn.specific = scoped: let
      global = Context.globalScope scoped.context;
    in {
      ${QueryScope.Packages} = global.pkgs;
      ${QueryScope.Lib} = global.lib;
    }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.show scoped}");

    fn.self = scoped: {
      ${QueryScope.Packages} = InputOutputs.pkgs scoped.context.inputOutputs.self;
      ${QueryScope.Lib} = InputOutputs.lib scoped.context.inputOutputs.self;
    }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.show scoped}");

    # queryAll :: ScopedContext -> { arg: ArgDesc, scope: QueryScope } -> Optional x
    fn.queryAll = scoped: { arg }: let
      scoped' = ScopedContext.byOffset scoped (ArgDesc.offset arg);
      lookup = Set.lookupAt (ArgDesc.components arg);
      queries = List.map lookup [
        (ScopedContext.global scoped')
        (ScopedContext.specific scoped')
        (ScopedContext.self scoped')
      ];
    in Opt.match (List.findIndex Opt.isJust queries) {
      inherit (Opt) nothing;
      just = i: List.index queries i;
    };

    # queryInput :: ScopedContext -> { arg: ArgDesc, scope: QueryScope, flake: Flake } -> Optional x
    fn.queryInput = scoped: { arg, inputName }: let
      context = Context.byOffset scoped.context (ArgDesc.offset arg);
      io = context.inputOutputs.${inputName};
      scope = {
        pkgs = InputOutputs.pkgs io;
        lib = InputOutputs.lib io;
      };
      outputs = {
        ${QueryScope.Packages} = scope.pkgs;
        ${QueryScope.Lib} = scope.lib;
      }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.show scoped}") // scope;
    in Set.lookupAt (ArgDesc.components arg) outputs;

    # query :: ScopedContext -> { arg: ArgDesc, scope: QueryScope } -> Optional x
    fn.query = scoped: { arg }: Opt.match (ArgDesc.inputName arg) {
      just = inputName: ScopedContext.queryInput scoped {
        inherit arg;
        inputName = Opt.match (CallFlake.canonicalizeInputName scoped.context.call inputName) {
          just = Fn.id;
          nothing = throw "Input ${inputName} not found for ${ArgDesc.show arg} in ${ScopedContext.show scoped}";
        };
      };
      nothing = ScopedContext.queryAll scoped {
        inherit arg;
      };
    };

    fn.callFn = scoped: fn: let
      inherit (scoped) context;
      callable = Callable.New {
        inherit fn;
        inputNames = CallFlake.allInputNames context.call;
      };
      autofill = name: arg: let
        nothing = throw "could not find ${ArgDesc.show arg} while evaluating ${ScopedContext.show scoped}";
        just = value: List.One { _0 = name; _1 = value; };
        maybe = value: Opt.match value {
          inherit just;
          nothing = List.Nil;
        };
        query = ScopedContext.query scoped {
          inherit arg;
        };
        value = ArgDesc.resolveValue arg query;
        /*strictValue = Opt.match value {
          inherit nothing;
          just = maybe;
        };*/
        lazyValue = Opt.match (ArgDesc.fallback arg) {
          just = fallback: Opt.match fallback {
            just = fallback: just (Opt.match query {
              just = Fn.id;
              nothing = fallback;
            });
            nothing = maybe query;
          };
          nothing = just (Opt.match query {
            inherit nothing;
            just = Fn.id;
          });
        };
      in lazyValue /*strictValue*/;
      implicitArgs = Set.fromList (List.concat (Set.mapToList autofill (Callable.args callable)));
    in Callable.callWith callable { inherit implicitArgs; };

    fn.callPackage = scoped: target: let
      fn = if Ty.function.check target then target else import target;
    in Fn.overridable (ScopedContext.callFn scoped fn);

    fn.callPackages = scoped: target: overrides: let
      target'fn = if Ty.function.check target || Ty.attrs.check target then target else import target;
      fn = ScopedContext.callFn scoped target'fn;
      attrNames = fn overrides;
      attrFor = name: Fn.copyArgs fn (args: (fn args).${name});
      packages = Set.map (name: _: Fn.overridable (attrFor name) overrides) attrNames;
      packageSet = Set.map (name: target:
        ScopedContext.callPackage (ScopedContext.push scoped name) target (overrides.${name} or { })
      ) target'fn;
    in if Ty.function.check target'fn then packages
      else if Ty.attrs.check target'fn then packageSet
      else throw "Expected package set when evaluating ${ScopedContext.show scoped}";

    fn.callPackageSet = scoped: target: overrides: let
      target'fn = if Ty.function.check target || Ty.attrs.check target then target else import target;
      overridesFor = component: { }; # TODO: get from FlConfig?
    in if Ty.function.check target'fn then ScopedContext.callFn scoped target'fn overrides
    else if Ty.attrs.check target'fn then ScopedContext.callPackages scoped target overrides
    else throw "Expected package set when evaluating ${ScopedContext.show scoped}";

    show = scoped: let
      context = Context.show scoped.context;
      path = Str.optional (scoped.path != [ ]) ".${Str.concatSep "." scoped.path}";
    in "ScopedContext.${scoped.scope}(${context})${path}";
  } // {
    New = {
      context
    , scope ? QueryScope.Default
    , path ? [ ]
    , outputs ? null
    }: ScopedContext.TypeId.new {
      inherit context scope path outputs;
    };

    Default = context: ScopedContext.New {
      inherit context;
    };
  };
}
