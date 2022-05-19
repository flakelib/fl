{ self, std }: let
  inherit (std.lib) Rec Enum Regex Str List Set Opt Null Fn Ty;
  inherit (self.lib.Fl) Callable;
  inherit (Callable) ArgDesc Offset;
in Rec.Def {
  name = "fl:Callable";
  Self = Callable;
  fields = {
    fn = { };
    inputNames = {
      default = [ ];
    };
  };

  fn.configData = callable: callable.fn.fl'config or { };
  fn.configDataArgs = callable: (Callable.configData callable).args or { };

  fn.argsConfig = callable: Set.map (name: config: ArgDesc.WithConfig {
    inherit name config;
  }) (Callable.configDataArgs callable);
  fn.argsFn = callable: Set.map (name: opt: ArgDesc.Parse {
    inherit name opt;
    inherit (callable) inputNames;
  }) (Fn.args callable.fn);

  # argsFallbacks :: Callable -> { string => a }
  fn.argsFallbacks = callable: let
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
  fn.args = callable: let
    config = Callable.argsConfig callable;
    fn = Callable.argsFn callable;
    all = config // fn;
    merge = name: fn: ((Opt.semigroup ArgDesc.semigroup).append
      (Opt.just fn)
      (Set.lookup name config)
    ).value;
  in Set.map merge all;

  fn.callWith = callable: {
    implicitArgs ? { }
  }: Fn.copyArgs callable.fn {
    inherit callable;
    implicitArgs = Callable.argsFallbacks callable // implicitArgs;
    __functor = self: { ... }@args: self.callable.fn (self.implicitArgs // args);
  };

  fn.call = callable: Callable.callWith callable { };

  fn.argNames = callable: Set.map (name: optional: ArgDesc.Parse {
    inherit name;
    inherit (callable) inputNames;
  }) (Fn.args callable.fn);
} // {
  New = {
    fn
  , inputNames ? [ ]
  }: Callable.TypeId.new {
    inherit fn inputNames;
  };

  Offset = Enum.Def {
    name = "fl:Callable.Offset";
    var = {
      None = "noOffset";
      Build = "build";
      Target = "target";
    };
  } // {
    Default = Offset.None;
  };

  ArgDesc = Rec.Def {
    name = "fl:Callable.ArgDesc";
    fields = {
      name.type = Ty.string;
      fallback = {
        type = Ty.nullOr Ty.opt;
        default = null;
      };
      inputName = {
        type = Ty.nullOr Ty.string;
        default = null;
      };
      offset = {
        type = Ty.nullOr Offset.TypeId.ty;
        default = null;
      };
      components = {
        type = Ty.nullOr (Ty.listOf Ty.string);
        default = null;
      };
    };

    fn.inputName = arg: Opt.fromNullable arg.inputName;
    fn.offset = arg: Null.match arg.offset {
      just = Fn.id;
      nothing = Offset.Default;
    };
    fn.fallback = arg: Opt.fromNullable arg.fallback;
    fn.fallbackValue = arg: Opt.monad.join (ArgDesc.fallback arg);

    fn.components = arg: Null.match arg.components {
      nothing = [ arg.name ];
      just = Fn.id;
    };

    fn.displayName = arg: Null.match arg.components {
      just = List.last;
      nothing = arg.name;
    };

    fn.isOptional = arg: arg.fallback != null;

    # resolveValue :: ArgDesc -> Optional x -> Optional (Optional x)
    fn.resolveValue = arg: value: Opt.match value {
      just = value: Opt.just (Opt.just value);
      nothing = ArgDesc.fallback arg;
    };

    # setFrom :: ArgDesc -> ArgDesc -> ArgDesc
    fn.setFrom = arg: new_arg: let
      new' = Set.retain [ "fallback" "inputName" "offset" "components" ] new_arg;
    in arg // Set.filter (_: v: v != null) new';

    show = arg: let
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
  } // {
    # New :: { name: string, fallback?: (Optional a)?, inputName?: string?, offset?: Offset?, components?: [string]? } -> ArgDesc
    New = {
      name
    , fallback ? null
    , inputName ? null
    , offset ? null
    , components ? null
    }: ArgDesc.TypeId.new {
      inherit name fallback inputName offset components;
    };

    # Parse :: { name: string, opt?: bool, inputNames?: [string] } -> ArgDesc
    Parse = {
      name
    , opt ? false
    , inputNames ? [ ]
    }: let
      inputRegex = Str.concatMapSep "|" (i: "^${i}") inputNames;
      offsetRegex = Str.concatMapSep "|" (o: "${o}$") (Enum.values Offset);
      parts = Regex.Splits "(${inputRegex})?'(${offsetRegex})?" name;
      mapCaptures = { captures, suffix, ... }: {
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
    in ArgDesc.New {
      inherit name;
      inherit (if parts.hasSplits then result else fastpath) inputName offset components;
      fallback = if opt then Opt.nothing else null;
    };

    WithConfig = {
      name
    , config ? { }
    }: ArgDesc.New {
      inherit name;
      fallback = if config ? fallback then Opt.just config.fallback else null;
      components = config.components or null;
      inputName = config.input or null;
      offset = config.offset or null;
    };

    semigroup = {
      append = a: b: ArgDesc.setFrom a b;
    };
  };
}
