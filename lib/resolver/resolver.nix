{ self, std }: let
  inherit (std.lib) Str List Set Opt Null Fn;
  inherit (self.lib) Callable Injectable ArgDesc Offset Regex;
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
      inputRegex = Str.concatMapSep "|" (i: "^${i}") inputNames;
      offsetRegex = Str.concatMapSep "|" (o: "${o}$") Offset.All;
      parts = Regex.splitExt "(${inputRegex})?'(${offsetRegex})?" name;
      mapCaptures = { captures, suffix }: {
        inputName = List.index captures 0;
        offset = List.index captures 1;
      };
      splits = List.map mapCaptures parts.splits;
      fastpath = {
        inputName = null;
        offset = null;
        components = [ name ];
      };
      inputName = (List.head splits).inputName;
      offset = (List.last splits).offset;
      hasInput = parts.prefix == "" && inputName != null;
      hasOffset = parts.suffix == "" && offset != null;
      components' = if hasInput then List.tail parts.strings else parts.strings;
      components = if hasOffset then List.init components' else components';
      result = {
        inherit inputName offset components;
      };
    in ArgDesc.new {
      inherit name;
      inherit (if parts.hasSplits then result else fastpath) inputName offset components;
      fallback = if opt then Opt.nothing else null;
    };

    withConfig = {
      name
    , config ? { }
    }: ArgDesc.new {
      inherit name;
      fallback = if config ? fallback then Opt.just config.fallback else null;
      components = config.components or null;
      inputName = config.input or null;
      offset = config.offset or null;
    };

    inputName = arg: Opt.fromNullable arg.inputName;
    offset = arg: Null.match arg.offset {
      just = Fn.id;
      nothing = Offset.Default;
    };
    fallback = arg: Opt.fromNullable arg.fallback;
    fallbackValue = arg: Opt.monad.join (ArgDesc.fallback arg);

    components = arg: Null.match arg.components {
      nothing = [ arg.name ];
      just = Fn.id;
    };

    displayName = arg: Null.match arg.components {
      just = List.last;
      nothing = arg.name;
    };

    isOptional = arg: arg.fallback != null;

    # resolveValue :: ArgDesc -> Optional x -> Optional (Optional x)
    resolveValue = arg: value: Opt.match value {
      just = value: Opt.just (Opt.just value);
      nothing = ArgDesc.fallback arg;
    };

    # setFrom :: ArgDesc -> ArgDesc -> ArgDesc
    setFrom = arg: new_arg: let
      new' = Set.retain [ "fallback" "inputName" "offset" "components" ] new_arg;
    in arg // Set.filter (_: v: v != null) new';

    describe = arg: let
      name = ArgDesc.displayName arg;
      inputName = Null.map (i: "${i}'") arg.inputName;
      offset = Null.map (o: "'${o}") arg.offset;
      components = if arg.components == [ name ] then null
        else Null.map (c: "${Str.concatSep "." c}") arg.components;
      at = Str.optional (inputName != null || components != null) "@";
      fallback = Null.map (f: Opt.match f {
        just = f: " ? ${f}";
        nothing = "?";
      }) arg.fallback;
      desc = [ name offset at inputName components fallback ];
    in Str.concat (List.filter (v: v != null) desc);

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

    configData = callable: callable.fn.fl'config or { };
    configDataArgs = callable: (Callable.configData callable).args or { };

    argsConfig = callable: Set.map (name: config: ArgDesc.withConfig {
      inherit name config;
    }) (Callable.configDataArgs callable);
    argsFn = callable: Set.map (name: opt: ArgDesc.parse {
      inherit name opt;
      inherit (callable) inputNames;
    }) (Fn.args callable.fn);

    # argsFallbacks :: Callable -> { string => a }
    argsFallbacks = callable: let
      args = Callable.args callable;
      fallbacks = Set.mapToList (name: arg: Opt.match (ArgDesc.fallbackValue arg) {
        nothing = List.Nil;
        just = fallback: Opt.match fallback {
          nothing = List.Nil;
          just = fallback: List.One { _0 = name; _1 = fallback; };
        };
      }) args;
    in Set.fromList (List.concat fallbacks);

    # args :: Callable -> {ArgDesc}
    args = callable: let
      config = Callable.argsConfig callable;
      fn = Callable.argsFn callable;
      all = config // fn;
      merge = name: fn: ((Opt.semigroup ArgDesc.semigroup).append
        (Opt.just fn)
        (Set.lookup name config)
      ).value;
    in Set.map merge all;

    callWith = callable: {
      implicitArgs ? { }
    }: Fn.copyArgs callable.fn {
      inherit callable;
      implicitArgs = Callable.argsFallbacks callable // implicitArgs;
      __functor = self: { ... }@args: self.callable.fn (self.implicitArgs // args);
    };

    call = callable: Callable.callWith callable { };

    argNames = callable: Set.map (name: optional: ArgDesc.parse {
      inherit name;
      inherit (callable) inputNames;
    }) (Fn.args callable.fn);
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
