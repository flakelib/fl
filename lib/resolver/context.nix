{ self, std }: let
  inherit (std.lib) Ty Str Bool List Set Fn Opt;
  inherit (self.lib)
    QueryScope
    Callable Injectable ArgDesc
    CallFlake Context ScopedContext
    BuildConfig System Offset
    FlakeInput InputConfig FlConfig
    InputOutputs;
in {
  Context = {
    TypeId = "fl:Context";
    # new :: set -> Context { buildConfig :: BuildConfig?, call :: CallFlake }
    new = {
      call
    , buildConfig ? null
    }: let
      inputConfigs = CallFlake.inputConfigs call;
      context = {
        type = Context.TypeId;
        inherit call buildConfig;
        inputOutputs = Set.map (name: flakeInput: InputOutputs.new rec {
          inherit context flakeInput;
          inputConfig = inputConfigs.${name};
          importMethod = Opt.toNullable (InputConfig.importMethod inputConfig);
        }) (CallFlake.filteredInputs call);
      };
    in context;

    byOffset = context: offset: Opt.match (Context.buildConfig context) {
      nothing = context;
      just = buildConfig:
        if Context.isNative context then context
        else Context.new {
          inherit (context) call;
          buildConfig = BuildConfig.byOffset buildConfig offset;
        };
      };

    byBuildConfig = context: buildConfig: Context.new {
      inherit (context) call;
      inherit buildConfig;
    };

    scopeFor = context: args: ScopedContext.new ({
      inherit context;
    } // args);

    callArgsFor = context: path: Set.atOr { } path (FlConfig.callArgs (FlakeInput.flConfig (CallFlake.flConfig context.call)));

    isNative = context: Opt.isJust (Context.buildConfig context) && BuildConfig.isNative context.buildConfig;
    orderedInputOutputs = context: List.map (name:
      Set.get name context.inputOutputs
    ) (CallFlake.orderedInputNames context.call);
    orderedOutputs = context: List.map (io: InputOutputs.outputs io) (Context.orderedInputOutputs context);

    buildConfig = context: Opt.fromNullable context.buildConfig;

    orderedInputNames = context:
      List.One "self" ++ Set.keys (Set.without [ "self" ] context.flakes);

    inputByName = context: inputName: Set.lookup inputName context.flakes;

    globalScope = context: {
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

    outputs = context: let
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

    describe = context: let
      self = CallFlake.describe context.call;
      bc = Opt.match (Context.buildConfig context) {
        just = bc: "(${BuildConfig.describe bc})";
        nothing = "";
      };
    in "${self}${bc}";
  };

  ScopedContext = {
    TypeId = "fl:ScopedContext";
    new = {
      context
    , scope ? QueryScope.Default
    , path ? [ ]
    , outputs ? null
    }: {
      type = ScopedContext.TypeId;
      inherit context scope path outputs;
    };

    Default = context: ScopedContext.new {
      inherit context;
    };

    push = scoped: path: scoped // {
      path = scoped.path ++ (List.From path);
    };

    byOffset = scoped: offset: scoped // {
      # TODO: use new
      context = Context.byOffset scoped.context offset;
    };

    global = scoped: Context.globalScope scoped.context // {
      callPackage = ScopedContext.callPackage scoped;
      callPackages = ScopedContext.callPackages scoped;
      callPackageSet = ScopedContext.callPackageSet scoped;
    };

    specific = scoped: let
      global = Context.globalScope scoped.context;
    in {
      ${QueryScope.Packages} = global.pkgs;
      ${QueryScope.Lib} = global.lib;
    }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.describe scoped}");

    self = scoped: {
      ${QueryScope.Packages} = InputOutputs.pkgs scoped.context.inputOutputs.self;
      ${QueryScope.Lib} = InputOutputs.lib scoped.context.inputOutputs.self;
    }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.describe scoped}");

    # queryAll :: ScopedContext -> { arg: ArgDesc, scope: QueryScope } -> Optional x
    queryAll = scoped: { arg }: let
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
    queryInput = scoped: { arg, inputName }: let
      context = Context.byOffset scoped.context (ArgDesc.offset arg);
      io = context.inputOutputs.${inputName};
      scope = {
        pkgs = InputOutputs.pkgs io;
        lib = InputOutputs.lib io;
      };
      outputs = {
        ${QueryScope.Packages} = scope.pkgs;
        ${QueryScope.Lib} = scope.lib;
      }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.describe scoped}") // scope;
    in Set.lookupAt (ArgDesc.components arg) outputs;

    # query :: ScopedContext -> { arg: ArgDesc, scope: QueryScope } -> Optional x
    query = scoped: { arg }: Opt.match (ArgDesc.inputName arg) {
      just = inputName: ScopedContext.queryInput scoped {
        inherit arg;
        inputName = Opt.match (CallFlake.canonicalizeInputName scoped.context.call inputName) {
          just = Fn.id;
          nothing = throw "Input ${inputName} not found for ${ArgDesc.describe arg} in ${ScopedContext.describe scoped}";
        };
      };
      nothing = ScopedContext.queryAll scoped {
        inherit arg;
      };
    };

    callFn = scoped: fn: let
      inherit (scoped) context;
      callable = Callable.new {
        inherit fn;
        inputNames = CallFlake.allInputNames context.call;
      };
      autofill = name: arg: let
        nothing = throw "could not find ${ArgDesc.describe arg} while evaluating ${ScopedContext.describe scoped}";
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

    callPackage = scoped: target: let
      fn = if Ty.function.check target then target else import target;
    in Fn.overridable (ScopedContext.callFn scoped fn);

    callPackages = scoped: target: overrides: let
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
      else throw "Expected package set when evaluating ${ScopedContext.describe scoped}";

    callPackageSet = scoped: target: overrides: let
      target'fn = if Ty.function.check target || Ty.attrs.check target then target else import target;
      overridesFor = component: { }; # TODO: get from FlConfig?
    in if Ty.function.check target'fn then ScopedContext.callFn scoped target'fn overrides
    else if Ty.attrs.check target'fn then ScopedContext.callPackages scoped target overrides
    else throw "Expected package set when evaluating ${ScopedContext.describe scoped}";

    describe = scoped: let
      context = Context.describe scoped.context;
      path = Str.optional (scoped.path != [ ]) ".${Str.concatSep "." scoped.path}";
    in "ScopedContext.${scoped.scope}(${context})${path}";
  };
}
