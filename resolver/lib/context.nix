{ self, std }: let
  inherit (std.lib) types string list set function optional;
  inherit (self.lib) flake resolver;
  rctx = self.lib.context;
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
      inherit context buildConfig inputs;
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
        ordered = [ contextScope context.scope.inputs ] ++ orderedInputs [];
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

  queryAll = context: { name, components, offset, ... }@arg: let
    mapScope = set.lookupAt components;
    scopes = list.map mapScope context.scope.ordered;
    ordered = optional.match (list.findIndex optional.isJust scopes) {
      nothing = optional.nothing;
      just = i: list.index scopes i;
    };
  in optional.match ordered {
    nothing = set.lookupAt components context.scope.global;
    inherit (optional) just;
  };

  query = context: { name, components ? [ name ], input ? null, offset ? null, optional ? false, fallback ? null, targetName ? null, ... }@arg: let
    inherit (std.lib) optional;
    arg'optional = arg.optional or false;
    base' = if input != null then context.scope.inputs.${input} else context.scope.global;
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
      else rctx.queryAll context (arg // { inherit name components offset fallback; });
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
    inputNames = set.keys context.scope.inputs;
    callable = resolver.parseCallable inputNames target;
    callArgs'' = set.map (_name: arg: rctx.query context (arg // { inherit targetName; })) callable.args;
    callArgs' = set.filter (_: optional.isJust) callArgs'';
    callArgs = set.map (_: v: v.value.item) callArgs';
  in if targetMode == "call" then callable.fn (callArgs // overrides)
    else if targetMode == "callAttrs" then set.map (targetName: target: rctx.callPackageCustomized {
      inherit context target targetName;
    }) target else throw "invalid targetMode";
}
