{ self, std }: let
  inherit (std.lib) Ty Rec Str Bool List Set Fn Opt;
  inherit (self.lib) Fl BuildConfig System;
  inherit (Fl) Context Desc Callable InputOutputs;
  inherit (Callable) ArgDesc Offset;
  inherit (Context) ScopedContext;
  inherit (InputOutputs) QueryScope;
  Outputs = std.lib.Flake.Outputs // self.lib.Flake.Outputs;
in Rec.Def {
  name = "fl:Context";
  Self = Context;
  fields = {
    desc.type = Desc.TypeId.ty;
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
        inherit (context) desc;
        buildConfig = BuildConfig.byOffset buildConfig offset;
      };
  };

  fn.byBuildConfig = context: buildConfig: Context.New {
    inherit (context) desc;
    inherit buildConfig;
  };

  fn.scopeFor = context: args: ScopedContext.New ({
    inherit context;
  } // args);

  fn.isNative = context: Opt.isJust (Context.buildConfig context) && BuildConfig.isNative context.buildConfig;
  fn.orderedInputOutputs = context: List.map (name:
    Set.get name context.inputOutputs
  ) (Desc.orderedInputNames context.desc);

  fn.buildConfig = context: Opt.fromNullable context.buildConfig;

  fn.globalScope.fn = context: {
    inherit context;
    inherit (context) buildConfig;
    inherit (context.desc) inputs;
    callPackage = ScopedContext.callPackage (Context.scopeFor context { });
    callPackages = ScopedContext.callPackages (Context.scopeFor context { });
    callPackageSet = ScopedContext.callPackageSet (Context.scopeFor context { });
    outputs = InputOutputs.outputs context.inputOutputs.self;
    pkgs = InputOutputs.MergeScopes (List.map (io: InputOutputs.namespacedPkgs io) (Context.orderedInputOutputs context));
    lib = InputOutputs.MergeScopes (List.map (io: InputOutputs.namespacedLib io) (Context.orderedInputOutputs context));
    buildPackages = (ScopedContext.global (Context.scopeFor (Context.byOffset context Offset.Build) {})).pkgs;
    targetPackages = (ScopedContext.global (Context.scopeFor (Context.byOffset context Offset.Target) {})).pkgs;
  };
  fn.globalScope.memoize = true;

  show = context: let
    self = Desc.show context.desc;
    bc = Opt.match (Context.buildConfig context) {
      just = bc: "(${BuildConfig.show bc})";
      nothing = "";
    };
  in "${self}${bc}";
} // {
  # New :: set -> Context { buildConfig :: BuildConfig?, desc :: Desc }
  New = {
    desc
  , buildConfig ? null
  }: let
    context = Context.TypeId.new {
      inherit desc buildConfig;
      inputOutputs = Desc.contextualInputOutputs desc context;
    };
  in context;

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
        inputName = Opt.match (Desc.canonicalizeInputName scoped.context.desc inputName) {
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
        inputNames = Desc.allInputNames context.desc;
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
      overridesFor = component: { }; # TODO: get from Fl.Config?
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
