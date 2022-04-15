{ self, std }: let
  inherit (std.lib) types string list set function optional;
  inherit (self.lib.resolver) flake resolver Context;
in {
  BuildConfig = {
    new = {
      system ? throw "must provide either `system` or `localSystem`"
    , localSystem ? { inherit system; }
    , crossSystem ? localSystem
    }: {
      inherit localSystem crossSystem;
    };

    isNative = bc: bc.localSystem == bc.crossSystem;
    #elaborate = lib.systems.elaborate;

    __functor = BuildConfig: arg:
      if types.string.check arg then BuildConfig.new { system = arg; }
      else BuildConfig.new arg;
  };

  InputConfig = {
    new = { name, config ? { } }: {
      inherit name config;
    };

    aliases = inputConfig: inputConfig.config.aliases or [ ];

    __functor = InputConfig: name: config: InputConfig.new {
      inherit name config;
    };
  };

  # new :: set -> Context { buildConfig :: Context.BuildConfig?, inputs :: [input], flakes :: [Flake] }
  new = {
    inputs
  , buildConfig ? null
  }: let
    context = {
      inherit inputs buildConfig;
    };
  in context;

  __functor = Context: inputs: buildConfig: Context.new {
    inherit inputs buildConfig;
  };

  flakes = context: set.map (name: input: let
    args = context.inputArgs.${name} or {};
  in flake.loadInput context input args) context.inputs;

  scope = context: let
    contextScope = {
      lib = mergeScopes [ "lib" ];
      builders = mergeScopes [ "builders" ];
      inherit context;
      inherit (context) buildConfig inputs;
      callPackage = target: overrides: Context.callPackageCustomized {
        inherit context target overrides;
      };
    };
    orderedInputs = attrPath: map (name: set.atOr {} ([ name ] ++ attrPath) scope.inputs) (Context.orderedInputNames context);
    mergeScopes = attrPath: list.foldl' set.semigroup.append {} (orderedInputs attrPath);
    flakes = Context.flakes context;
    scope = {
      inputs = set.map (_: name: scope.inputs.${name}) (Context.inputAliases context) // set.map (name: _:
        flakes.${name} // flakes.${name}.builders or { } // flakes.${name}.packages or { }
      ) context.inputs;
      ordered = [ contextScope scope.inputs ] ++ orderedInputs [];
      global = mergeScopes [] // contextScope;
    };
  in scope;

  inputConfigs = context: set.map (name: _: Context.InputConfig.new {
    inherit name;
    config = context.inputs.self.flakes.config.inputs.${name} or { };
  }) context.inputs;

  # { alias: inputName }
  inputAliases = context: let
    inputConfigs = Context.inputConfigs context;
    aliasPairs = name: inputConfig: list.map (alias: { _0 = alias; _1 = name; }) (Context.InputConfig.aliases inputConfig);
  in set.fromList (list.concat (set.mapToList aliasPairs inputConfigs));

  orderedInputNames = context:
    set.keys (set.without [ "self" ] context.inputs) ++ list.singleton "self";

  inputNames = context:
    Context.orderedInputNames context ++ set.keys (Context.inputAliases context);

  importScope = context: set.optional (context.buildConfig != null) {
    inherit (context.buildConfig) localSystem crossSystem;
  } // context.importScope or {} // {
    # TODO: consider what should actually be here
    inherit (context) buildConfig;
    inherit context;
  };

  queryAll = context: { name, components, offset, ... }@arg: let
    mapScope = set.lookupAt components;
    scope = Context.scope context;
    scopes = list.map mapScope scope.ordered;
    ordered = optional.match (list.findIndex optional.isJust scopes) {
      nothing = optional.nothing;
      just = i: list.index scopes i;
    };
  in optional.match ordered {
    nothing = set.lookupAt components scope.global;
    inherit (optional) just;
  };

  query = context: { name, components ? [ name ], input ? null, offset ? null, optional ? false, fallback ? null, targetName ? null, ... }@arg: let
    inherit (std.lib) optional;
    arg'optional = arg.optional or false;
    scope = Context.scope context;
    base' = if input != null then scope.inputs.${input} else scope.global;
    offsetAttr = "${offset}Packages"; # TODO: this better
    base = if offset != null then base'.${offsetAttr} else base';
    hasScope = input != null && (offset == null || base' ? ${offsetAttr});
    fallback =
      if arg ? fallback then optional.just fallback
      else if arg'optional then optional.nothing
      else throw ("attr `${name}` not found"
        + string.optional (targetName != null) " when calling `${targetName}`"
        + string.optional (input != null) " in input ${input}"
      );
    value = if hasScope
      then set.lookupAt components base # TODO: parseInjectable at every attr access here
      else Context.queryAll context (arg // { inherit name components offset fallback; });
    result = optional.match value {
      nothing = fallback;
      inherit (optional) just;
    };
  in optional.functor.map (resolver.parseInjectable context) result;

  callPackageCustomized = {
    context
  , target
  , targetName ? null
  , targetMode ?
    if types.function.check target then "call"
    else if types.attrs.check target then "callAttrs"
    else if types.path.check target then "callPath"
    else throw "cannot detect targetMode" + string.optional (targetName != null) " for ${targetName}"
  , overrides ? { }
  }: let
    callable = resolver.parseCallable (Context.inputNames context) target;
    callArgs'' = set.map (_name: arg: Context.query context (arg // { inherit targetName; })) callable.args;
    callArgs' = set.filter (_: optional.isJust) callArgs'';
    callArgs = set.map (_: v: v.value.item) callArgs';
  in if targetMode == "call" then callable.fn (callArgs // overrides)
    else if targetMode == "callAttrs" then set.map (targetName: target: Context.callPackageCustomized {
      inherit context target targetName;
    }) target else throw "invalid targetMode";
}
