{ self, std }: let
  inherit (std.lib) string list set optional nullable function;
  inherit (self.lib) Callable Injectable ArgDesc Offset util;
in {
  ArgDesc = {
    TypeId = "fl:ArgDesc";
    # new :: { name: string, fallback?: (Optional a)?, inputName?: string?, offset?: Offset?, components?: [string]? } -> ArgDesc
    new = {
      name
    , fallback ? null
    , inputName ? null
    , offset ? null
    , components ? null
    }: {
      type = ArgDesc.TypeId;
      inherit name fallback inputName offset components;
    };

    # parse :: { name: string, opt?: bool, inputNames?: [string] } -> ArgDesc
    parse = {
      name
    , opt ? false
    , inputNames ? [ ]
    }: let
      inputRegex = string.concatMapSep "|" (i: "^${i}") inputNames;
      offsetRegex = string.concatMapSep "|" (o: "${o}$") Offset.All;
      parts = util.regex.splitExt "(${inputRegex})?'(${offsetRegex})?" name;
      mapCaptures = { captures, suffix }: {
        inputName = list.index captures 0;
        offset = list.index captures 1;
      };
      splits = list.map mapCaptures parts.splits;
      fastpath = {
        inputName = null;
        offset = null;
        components = [ name ];
      };
      inputName = (list.head splits).inputName;
      offset = (list.last splits).offset;
      hasInput = parts.prefix == "" && inputName != null;
      hasOffset = parts.suffix == "" && offset != null;
      components' = if hasInput then list.tail parts.strings else parts.strings;
      components = if hasOffset then list.init components' else components';
      result = {
        inherit inputName offset components;
      };
    in ArgDesc.new {
      inherit name;
      inherit (if parts.hasSplits then result else fastpath) inputName offset components;
      fallback = if opt then optional.nothing else null;
    };

    withConfig = {
      name
    , config ? { }
    }: ArgDesc.new {
      inherit name;
      fallback = if config ? fallback then optional.just config.fallback else null;
      components = config.components or null;
      inputName = config.input or null;
      offset = config.offset or null;
    };

    inputName = arg: optional.fromNullable arg.inputName;
    offset = arg: nullable.match arg.offset {
      just = function.id;
      nothing = Offset.Default;
    };
    fallback = arg: optional.fromNullable arg.fallback;
    fallbackValue = arg: optional.monad.join (ArgDesc.fallback arg);

    components = arg: nullable.match arg.components {
      nothing = [ arg.name ];
      just = function.id;
    };

    displayName = arg: nullable.match arg.components {
      just = list.last;
      nothing = arg.name;
    };

    isOptional = arg: arg.fallback != null;

    # resolveValue :: ArgDesc -> Optional x -> Optional (Optional x)
    resolveValue = arg: value: optional.match value {
      just = value: optional.just (optional.just value);
      nothing = ArgDesc.fallback arg;
    };

    # setFrom :: ArgDesc -> ArgDesc -> ArgDesc
    setFrom = arg: new_arg: let
      new' = set.retain [ "fallback" "inputName" "offset" "components" ] new_arg;
    in arg // set.filter (_: v: v != null) new';

    describe = arg: let
      inputName = nullable.functor.map (i: "${i}'") arg.inputName;
      offset = nullable.functor.map (o: "'${o}") arg.offset;
      components = nullable.functor.map (c: "${string.concatSep "." c}") arg.components;
      at = string.optional (inputName != null || components != null) "@";
      fallback = nullable.functor.map (f: optional.match f {
        just = f: " ? ${f}";
        nothing = "?";
      }) arg.fallback;
      desc = [ (ArgDesc.displayName arg) offset at inputName components fallback ];
    in string.concat (list.filter (v: v != null) desc);

    semigroup = {
      append = a: b: ArgDesc.setFrom a b;
    };
  };
  Offset = {
    None = "noOffset";
    Build = "build";
    Target = "target";

    All = [ Offset.None Offset.Build Offset.Target ];
    Default = Offset.None;
  };

  Callable = {
    new = {
      fn
    , inputNames ? [ ]
    }: {
      inherit fn inputNames;
    };

    configData = callable: callable.fl'config or { };
    configDataArgs = callable: (Callable.configData callable).args or { };

    argsConfig = callable: set.map (name: config: ArgDesc.withConfig {
      inherit name config;
    }) (Callable.configDataArgs callable);
    argsFn = callable: set.map (name: opt: ArgDesc.parse {
      inherit name opt;
      inherit (callable) inputNames;
    }) (function.args callable.fn);

    argsFallbacks = callable: let
      args = Callable.args callable;
      fallbacks = set.mapToList (name: arg: optional.match (ArgDesc.fallbackValue arg) {
        nothing = list.nil;
        just = fallback: list.singleton { _0 = name; _1 = fallback; };
      }) args;
    in set.fromList (list.concat fallbacks);

    # args :: Callable -> {ArgDesc}
    args = callable: let
      config = Callable.argsConfig callable;
      fn = Callable.argsFn callable;
      all = config // fn;
      merge = name: fn: ((optional.semigroup ArgDesc.semigroup).append
        (optional.just fn)
        (set.lookup name config)
      ).value;
    in set.map merge all;

    callWith = callable: {
      implicitArgs ? { }
    }: function.copyArgs callable.fn {
      inherit callable;
      implicitArgs = Callable.argsFallbacks callable // implicitArgs;
      __functor = self: { ... }@args: self.callable.fn (self.implicitArgs // args);
    };

    call = callable: Callable.callWith callable { };

    argNames = callable: set.map (name: optional: ArgDesc.parse {
      inherit name;
      inherit (callable) inputNames;
    }) (function.args callable.fn);
  };

  Injectable = {
    TypeId = "fl:Injectable";
    new = {
      item
    , context
    , callable
    }: {
      type = Injectable.TypeId;
      inherit item context callable;
    };

    result = injectable: injectable.item;
  };

  parseInjectable = context: item: {
    # do things like splicing and customization here?
    inherit item;
  };
}
