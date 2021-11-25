{ self'lib, lib }: with lib; let
  inherit (builtins) split length elemAt genList;
  inherit (self'lib) loadInputWith;

  foldAttrList = foldl (r: l: r // l) {};

  toFunctor = f: if builtins.isFunction f then {
    __functor = self: f;
  } else f;

  splitWith = {
    pattern
  , string
  , mapCaptures ? captures: suffix: captures
  }: let
    inner = split pattern string;
    len = length inner;
    count = len / 2;
    prefix = elemAt inner 0;
    splits = genList (i: let
      captures = elemAt inner (1 + i * 2);
      suffix = elemAt inner (2 + i * 2);
    in {
      inherit suffix;
      captures = mapCaptures captures suffix;
    }) count;
    hasSplits = len != 1;
  in {
    inherit inner count prefix splits hasSplits;
    suffix = if hasSplits then last inner else null;
    strings = [ prefix ] ++ map ({ captures, suffix }: suffix) splits;
  };

  parseArgName = inputNames: name: let
    offsetNames = [ "build" "target" ];
    inputRegex = concatMapStringsSep "|" (i: "^${i}") inputNames;
    offsetRegex = concatMapStringsSep "|" (o: "${o}$") offsetNames;
    parts = splitWith {
      pattern = "(${inputRegex})?'(${offsetRegex})?";
      string = name;
      mapCaptures = captures: suffix: {
        input = elemAt captures 0;
        offset = elemAt captures 1;
      };
    };
    fastpath = {
      inherit name;
      input = null;
      offset = null;
      components = [ name ];
    };
    input = (head parts.splits).captures.input;
    offset = (last parts.splits).captures.offset;
    hasInput = parts.prefix == "" && input != null;
    hasOffset = parts.suffix == "" && offset != null;
    components' = if hasInput then tail parts.strings else parts.strings;
    components = if hasOffset then init components' else components';
    result = {
      inherit name input offset components;
    };
  in if parts.hasSplits then result else fastpath;

  parseCallable = inputNames: fn: let
    args = functionArgs fn;
    argNames = attrNames args;
    extraConfig = fn.callConfig or { };
    mapArg = argName: optional: let
      argConfig = extraConfig.args.${argName} or { };
      fallback = argConfig.fallback or null;
    in parseArgName inputNames argName // {
      ${if argConfig ? input then "input" else null} = argConfig.input;
      ${if argConfig ? offset then "offset" else null} = argConfig.offset;
      optional = argConfig.optional or (fallback != null || optional);
      inherit fallback;
    };
  in {
    inherit fn;
    args = mapAttrs mapArg args;
  };

  parseInjectable = context: item: let
    spliced = if context.buildConfig != null then item.__spliced.splicer {
      fn = item.__spliced.fn;
      inherit (context) buildConfig;
    } else item.__spliced.fn;
    # do things like splicing here
  in if item ? __spliced.fn then builtins.trace "aaaa" spliced else item;

  makeContext = {
    inputs
  , buildConfig ? null
  }: let
    mapInput = name: input: loadInputWith {
      inherit input inputs name buildConfig; # context?
    };
    aliases = mapAttrsToList (name: input:
      map (alias: nameValuePair alias context.scope.inputs.${name}) input.flakes.config.aliases or [ ]
    ) inputs;
    orderedInputs = attrNames inputs;
    mergeScopes = attrPath: foldAttrList (map (name: attrByPath ([ name ] ++ attrPath) {} context.scope.inputs) orderedInputs);
    context = {
      inputs = mapAttrs mapInput inputs;
      scope = {
        inputs = listToAttrs (concatLists aliases) // mapAttrs (name: _:
          context.inputs.${name} // context.inputs.${name}.builders or { } // context.inputs.${name}.packages or { }
        ) inputs;
        global = mergeScopes [] // {
          lib = mergeScopes [ "lib" ];
          builders = mergeScopes [ "builders" ];
          inherit buildConfig;
        };
      };
      inherit buildConfig;
    };
  in context;

  callPackageCustomized = {
    context
  , target
  , targetName ? null
  , targetMode ?
    if isFunction target then "call"
    else if isAttrs target then "callAttrs"
    else throw "cannot detect targetMode"
  , overrides ? { }
  }: let
    inputNames = attrNames context.scope.inputs;
    callable = parseCallable inputNames target;
    callArgs = mapAttrs (name: arg: let
      base' = if arg.input != null then context.scope.inputs.${arg.input} else context.scope.global;
      offsetAttr = "${arg.offset}Packages"; # TODO: this better
      base = if arg.offset != null then base'.${offsetAttr} else base';
      fallback =
        if arg.fallback != null then arg.fallback
        else if arg.optional then null
        else throw ("attr `${name}` not found"
          + optionalString (targetName != null) " when calling `${targetName}`"
          + optionalString (arg.input != null) " in input ${arg.input}"
        );
      value = attrByPath arg.components fallback base; # TODO: parseInjectable at every attr access here
      result = parseInjectable context value;
    in result) callable.args;
  in if targetMode == "call" then callable.fn (callArgs // overrides)
    else if targetMode == "callAttrs" then mapAttrs (targetName: target: callPackageCustomized {
      inherit context target targetName;
    }) target else throw "invalid targetMode";

  makeCallPackage = { scope, inputs, buildConfig }@context: target: overrides: callPackageCustomized {
    inherit context target overrides;
  };

  spliceFn = { fn, splicer }: toFunctor fn // {
    __spliced = {
      inherit splicer;
    };
  };
in {
  inherit splitWith parseArgName parseCallable parseInjectable makeCallPackage spliceFn callPackageCustomized makeContext;
}
