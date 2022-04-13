{ self, std }: let
  inherit (std.lib) string list set function;
  inherit (self.lib.resolver) util resolver;
in {
  parseArgName = inputNames: name: let
    offsetNames = [ "build" "target" ];
    inputRegex = string.concatMapSep "|" (i: "^${i}") inputNames;
    offsetRegex = string.concatMapSep "|" (o: "${o}$") offsetNames;
    parts = util.regex.splitExt "(${inputRegex})?'(${offsetRegex})?" name;
    mapCaptures = { captures, suffix }: {
      input = list.index captures 0;
      offset = list.index captures 1;
    };
    splits = list.map mapCaptures parts.splits;
    fastpath = {
      inherit name;
      input = null;
      offset = null;
      components = [ name ];
    };
    input = (list.head splits).input;
    offset = (list.last splits).offset;
    hasInput = parts.prefix == "" && input != null;
    hasOffset = parts.suffix == "" && offset != null;
    components' = if hasInput then list.tail parts.strings else parts.strings;
    components = if hasOffset then list.init components' else components';
    result = {
      inherit name input offset components;
    };
  in if parts.hasSplits then result else fastpath;

  parseCallable = inputNames: fn: let
    args = function.args fn;
    argNames = set.keys args;
    extraConfig = fn.res'config or { };
    mapArg = argName: optional: let
      argConfig = extraConfig.args.${argName} or { };
    in resolver.parseArgName inputNames argName // {
      ${if argConfig ? input then "input" else null} = argConfig.input;
      ${if argConfig ? offset then "offset" else null} = argConfig.offset;
      optional = argConfig.optional or (argConfig ? fallback || optional);
      ${if argConfig ? fallback then "fallback" else null} = argConfig.fallback;
    };
  in {
    inherit fn;
    args = set.map mapArg args;
  };

  parseInjectable = context: item: {
    # do things like splicing and customization here?
    inherit item;
  };
}
