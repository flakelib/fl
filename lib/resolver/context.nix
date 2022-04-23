{ self, std }: let
  inherit (std.lib) types string bool list set function optional;
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
        inputOutputs = set.map (name: flakeInput: InputOutputs.new rec {
          inherit context flakeInput;
          inputConfig = inputConfigs.${name};
          importMethod = optional.toNullable (InputConfig.importMethod inputConfig);
        }) (CallFlake.filteredInputs call);
      };
    in context;

    byOffset = context: offset:
      if optional.isNothing (Context.buildConfig context) || Context.isNative context then context
      else Context.new {
        inherit (context) call;
        buildConfig = BuildConfig.byOffset offset;
      };

    byBuildConfig = context: buildConfig: Context.new {
      inherit (context) call;
      inherit buildConfig;
    };

    scopeFor = context: args: ScopedContext.new ({
      inherit context;
    } // args);

    callArgsFor = context: path: set.atOr { } path (FlConfig.callArgs (FlakeInput.flConfig (CallFlake.flConfig context.call)));

    isNative = context: optional.isJust (Context.buildConfig context) && BuildConfig.isNative context.buildConfig;
    orderedInputOutputs = context: list.map (name:
      set.get name context.inputOutputs
    ) (CallFlake.orderedInputNames context.call);
    orderedOutputs = context: list.map (io: InputOutputs.outputs io) (Context.orderedInputOutputs context);

    buildConfig = context: optional.fromNullable context.buildConfig;

    orderedInputNames = context:
      list.singleton "self" ++ set.keys (set.without [ "self" ] context.flakes);

    inputByName = context: inputName: set.lookup inputName context.flakes;

    globalScope = context: {
      inherit context;
      inherit (context) buildConfig;
      callPackage = Context.callPackage context;
      callPackages = Context.callPackages context;
      callPackageSet = Context.callPackageSet context;
      inputs = CallFlake.flakeInputs context.call;
      outputs = InputOutputs.outputs context.inputOutputs.self;
      pkgs = InputOutputs.MergeScopes (list.map (io: InputOutputs.namespacedPkgs io) (Context.orderedInputOutputs context));
      lib = InputOutputs.MergeScopes (list.map (io: InputOutputs.namespacedLib io) (Context.orderedInputOutputs context));
      buildPackages = (ScopedContext.globalScope (ScopedContext.scopeFor (Context.byOffset Offset.Build) {})).pkgs;
      targetPackages = (ScopedContext.globalScope (ScopedContext.scopeFor (Context.byOffset Offset.Target) {})).pkgs;
    };

    outputs = context: let
      args = CallFlake.args context.call;
      packageSets = set.retain (FlakeInput.NativePackageSetAttrs ++ FlakeInput.FlNativePackageSetAttrs) args;
      attrOf = name: bool.toNullable (args ? ${name}) name;
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
      mapDefault = defaults: fn: default: if types.string.check default
        then defaults.${default} or (throw "TODO: couldn't find default ${default}")
        else fn default;
      staticAttrs = set.retain FlakeInput.StaticAttrs args // {
        flakes = CallFlake.flOutput context.call;
        ${attrOf "lib"} = ScopedContext.callPackageSet (Context.scopeFor context {
          inherit outputs;
          scope = QueryScope.Lib;
          path = [ "lib" ];
        }) args.lib (Context.callArgsFor context [ "lib" ]);
        ${attrOf "overlay"} = mapDefault outputs.overlays function.id args.overlay;
        ${attrOf "nixosModule"} = mapDefault outputs.nixosModules function.id args.nixosModule;
        ${attrOf "defaultTemplate"} = mapDefault outputs.templates function.id args.defaultTemplate;
        ${attrOf "defaultPackage"} = mapDefault outputs.packages (callPackageAt "defaultPackage") args.defaultPackage;
        ${attrOf "defaultApp"} = mapDefault outputs.apps (callPackageAt "defaultApp") args.defaultApp;
        ${attrOf "devShell"} = mapDefault outputs.devShells (callPackageAt "devShell") args.devShell;
        # TODO: builders
      };
      nativeAttrs = set.map callPackageSetAt packageSets;
      outputs = staticAttrs // nativeAttrs;
    in outputs;

    describe = context: let
      self = CallFlake.describe context.call;
      bc = optional.match (Context.buildConfig context) {
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
      path = scoped.path ++ (if (types.listOf types.string).check path then path else list.singleton path);
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

    # queryAll :: ScopedContext -> { arg: ArgDesc, scope: QueryScope } -> Optional x
    queryAll = scoped: { arg }: let
      lookup = set.lookupAt (ArgDesc.components arg);
      queries = list.map lookup [
        (ScopedContext.global scoped)
        (ScopedContext.specific scoped)
      ];
    in optional.match (list.findIndex optional.isJust queries) {
      nothing = optional.nothing;
      just = i: list.index queries i;
    };

    # queryInput :: ScopedContext -> { arg: ArgDesc, scope: QueryScope, flake: Flake } -> Optional x
    queryInput = scoped: { arg, inputName }: let
      context = Context.byOffset scoped.context (ArgDesc.offset arg);
      io = scoped.context.inputOutputs.${inputName};
      scope = {
        pkgs = InputOutputs.pkgs io;
        lib = InputOutputs.lib io;
      };
      outputs = {
        ${QueryScope.Packages} = scope.pkgs;
        ${QueryScope.Lib} = scope.lib;
      }.${scoped.scope} or (throw "Unsupported QueryScope in ${ScopedContext.describe scoped}") // scope;
    in set.lookupAt (ArgDesc.components arg) outputs;

    # query :: ScopedContext -> { arg: ArgDesc, scope: QueryScope } -> Optional x
    query = scoped: { arg }: optional.match (ArgDesc.inputName arg) {
      just = inputName: ScopedContext.queryInput scoped {
        inherit arg;
        inputName = optional.match (CallFlake.canonicalizeInputName scoped.context.call inputName) {
          just = function.id;
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
        just = value: list.singleton { _0 = name; _1 = value; };
        maybe = value: optional.match value {
          inherit just;
          nothing = list.nil;
        };
        query = ScopedContext.query scoped {
          inherit arg;
        };
        value = ArgDesc.resolveValue arg query;
        /*strictValue = optional.match value {
          inherit nothing;
          just = maybe;
        };*/
        lazyValue = optional.match (ArgDesc.fallback arg) {
          just = fallback: optional.match fallback {
            just = fallback: just (optional.match query {
              just = function.id;
              nothing = fallback;
            });
            nothing = maybe query;
          };
          nothing = just (optional.match query {
            inherit nothing;
            just = function.id;
          });
        };
      in lazyValue /*strictValue*/;
      implicitArgs = set.fromList (list.concat (set.mapToList autofill (Callable.args callable)));
    in Callable.callWith callable { inherit implicitArgs; };

    callPackage = scoped: target: let
      fn = if types.function.check target then target else import target;
    in function.overridable (ScopedContext.callFn scoped target);

    callPackages = scoped: target: overrides: let
      target'fn = if types.function.check target || types.attrs.check target then target else import target;
      fn = ScopedContext.callFn scoped target'fn;
      attrNames = fn overrides;
      attrFor = name: function.copyArgs fn (args: (fn args).${name});
      packages = set.map (name: _: function.overridable (attrFor name) overrides) attrNames;
      packageSet = set.map (name: target:
        ScopedContext.callPackage (ScopedContext.push scoped name) target (overrides.${name} or { })
      ) target'fn;
    in if types.function.check target'fn then packages
      else if types.attrs.check target'fn then packageSet
      else throw "Expected package set when evaluating ${ScopedContext.describe scoped}";

    callPackageSet = scoped: target: overrides: let
      target'fn = if types.function.check target || types.attrs.check target then target else import target;
      overridesFor = component: { }; # TODO: get from FlConfig?
    in if types.function.check target'fn then ScopedContext.callFn scoped target'fn overrides
    else if types.attrs.check target'fn then ScopedContext.callPackages scoped target overrides
    else throw "Expected package set when evaluating ${ScopedContext.describe scoped}";

    describe = scoped: let
      context = Context.describe scoped.context;
      path = string.optional (scoped.path != [ ]) ".${string.concatSep "." scoped.path}";
    in "ScopedContext.${scoped.scope}(${context})${path}";
  };
}
