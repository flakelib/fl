{ self, std }: let
  inherit (std.lib) types string list set function optional;
  inherit (self.lib) flake context resolver;
in {
  buildConfig = {
    new = {
      system ? throw "must provide either `system` or `localSystem`"
    , localSystem ? { inherit system; }
    , crossSystem ? localSystem
    }: {
      inherit localSystem crossSystem;
    };

    isNative = bc: bc.localSystem == bc.crossSystem;
    #elaborate = lib.systems.elaborate;

    __functor = self: arg:
      if types.string.check arg then self.new { system = arg; }
      else self.new arg;
  };

  new = {
    inputs
  , buildConfig ? null
  }: let
    mapInput = name: input: flake.loadInput context input context.inputArgs.${name} or {};
    aliases = set.mapToList (name: input:
      list.map (alias: { _0 = alias; _1 = context.scope.inputs.${name}; }) input.flakes.config.aliases or [ ]
    ) inputs;
    contextScope = {
      lib = mergeScopes [ "lib" ];
      builders = mergeScopes [ "builders" ];
      inherit context buildConfig;
    };
    orderedInputNames = set.keys (set.without [ "self" ] inputs) ++ list.singleton "self";
    orderedInputs = attrPath: map (name: set.atOr {} ([ name ] ++ attrPath) context.scope.inputs) orderedInputNames;
    mergeScopes = attrPath: list.foldl' set.semigroup.append {} (orderedInputs attrPath);
    context = {
      inputs = set.map mapInput inputs;
      scope = {
        inputs = set.fromList (list.concat aliases) // set.map (name: _:
          context.inputs.${name} // context.inputs.${name}.builders or { } // context.inputs.${name}.packages or { }
        ) inputs;
        ordered = list.singleton contextScope ++ orderedInputs [];
        global = mergeScopes [] // contextScope;
      };
      inherit buildConfig;
    };
  in context;

  __functor = self: inputs: buildConfig: self.new {
    inherit inputs buildConfig;
  };

  importScope = context: set.optional (context.buildConfig != null) {
    inherit (context.buildConfig) localSystem crossSystem;
  } // context.importScope or {} // {
    # TODO: consider what should actually be here
    inherit (context) buildConfig;
    inherit context;
  };

  queryAll = context: { name, components, offset, fallback, ... }@arg: let
    mapScope = set.lookupAt components;
    scopes = list.map mapScope context.scope.ordered;
    ordered = optional.match (list.findIndex optional.isJust scopes) {
      nothing = optional.nothing;
      just = i: list.index scopes i;
    };
  in optional.match ordered {
    nothing = set.atOr fallback components context.scope.global;
    just = function.id;
  };

  query = context: { name, components ? [ name ], input ? null, offset ? null, optional ? false, fallback ? null, targetName ? null, ... }@arg: let
    base' = if input != null then context.scope.inputs.${input} else context.scope.global;
    offsetAttr = "${offset}Packages"; # TODO: this better
    base = if offset != null then base'.${offsetAttr} else base';
    hasScope = input != null && (offset == null || base' ? ${offsetAttr});
    marker = { __'notFound = true; };
    fallback =
      if arg ? fallback then fallback
      else if optional then marker
      else throw ("attr `${name}` not found"
        + string.optional (targetName != null) " when calling `${targetName}`"
        + string.optional (input != null) " in input ${input}"
      );
    value = if hasScope
      then set.atOr fallback components base # TODO: parseInjectable at every attr access here
      else context.queryAll context (arg // { inherit name components offset fallback; });
    result = resolver.parseInjectable context value;
  in if value == marker then null else result;

  # TODO: rewrite this and split it up!!
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
    inputNames = set.keys context.scope.inputs;
    callable = resolver.parseCallable inputNames target;
    callArgs'' = set.map (_name: arg: context.query context (arg // { inherit targetName; })) callable.args;
    callArgs' = set.filter (_: v: v != null) callArgs'';
    callArgs = set.map (_: v: v.item) callArgs';
  in if targetMode == "call" then callable.fn (callArgs // overrides)
    else if targetMode == "callAttrs" then set.map (targetName: target: context.callPackageCustomized {
      inherit context target targetName;
    }) target else throw "invalid targetMode";
}
