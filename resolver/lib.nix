{ self, std }: let
  inherit (std) flake types string bool list set regex function;
  resolver = self.lib;
in {
  resolver = {
    parseArgName = inputNames: name: let
      offsetNames = [ "build" "target" ];
      inputRegex = string.concatMapSep "|" (i: "^${i}") inputNames;
      offsetRegex = string.concatMapSep "|" (o: "${o}$") offsetNames;
      parts = resolver.util.regex.splitExt "(${inputRegex})?'(${offsetRegex})?" name;
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
      in resolver.resolver.parseArgName inputNames argName // {
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
  };

  context.buildConfig = {
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

  context = {
    new = inputs: buildConfig: let
      mapInput = name: input: resolver.flake.loadInput context input context.inputArgs.${name} or {};
      aliases = set.mapToList (name: input:
        list.map (alias: { _0 = alias; _1 = context.scope.inputs.${name}; }) input.flakes.config.aliases or [ ]
      ) inputs;
      orderedInputs = set.keys inputs;
      mergeScopes = attrPath: list.foldl' set.semigroup.append {} (map (name: set.atOr {} ([ name ] ++ attrPath) context.scope.inputs) orderedInputs);
      context = {
        inputs = set.map mapInput inputs;
        scope = {
          inputs = set.fromList (list.concat aliases) // set.map (name: _:
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

    importScope = context: set.optional (context.buildConfig != null) {
      inherit (context.buildConfig) localSystem crossSystem;
    } // context.importScope or {} // {
      # TODO: consider what should actually be here
      inherit (context) buildConfig;
      inherit context;
    };

    query = context: { name, components ? [ name ], input ? null, offset ? null, optional ? false, fallback ? null, targetName ? null, ... }@arg: let
      base' = if input != null then context.scope.inputs.${input} else context.scope.global;
      offsetAttr = "${offset}Packages"; # TODO: this better
      base = if offset != null then base'.${offsetAttr} else base';
      marker = { __'notFound = true; };
      fallback =
        if arg ? fallback then fallback
        else if optional then marker
        else throw ("attr `${name}` not found"
          + string.optional (targetName != null) " when calling `${targetName}`"
          + string.optional (input != null) " in input ${input}"
        );
      value = set.atOr fallback components base; # TODO: parseInjectable at every attr access here
      result = resolver.resolver.parseInjectable context value;
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
      callable = resolver.resolver.parseCallable inputNames target;
      callArgs'' = set.map (_name: arg: resolver.context.query context (arg // { inherit targetName; })) callable.args;
      callArgs' = set.filter (_: v: v != null) callArgs'';
      callArgs = set.map (_: v: v.item) callArgs';
    in if targetMode == "call" then callable.fn (callArgs // overrides)
      else if targetMode == "callAttrs" then set.map (targetName: target: resolver.context.callPackageCustomized {
        inherit context target targetName;
      }) target else throw "invalid targetMode";
  };

  flake = {
    # importInput :: context -> input -> args -> resolved
    importInput = context: input: let
      hasImport = builtins.pathExists "${toString input}/default.nix";
      imported = import input;
      fallback =
        if !hasImport then {}: {}
        else if types.function.check imported then imported
        else {}: imported;
      importer = input.flakes.import or fallback;
      scope = resolver.context.importScope context;
    in function.wrapScoped scope importer;

    # loadInput :: context -> input -> args -> resolved
    loadInput = context: input: args: let
      inherit (context.buildConfig.localSystem) system;
      isBuild = context.buildConfig != null;
      isNative = isBuild && resolver.context.buildConfig.isNative context.buildConfig;
      useNative = isNative && args == { };
      outputs = { # TODO: do not use `outputs` since it already exists? or idk :<
        packages = input.packages.${system} or { };
        legacyPackages = input.legacyPackages.${system} or { };
        checks = input.checks.${system} or { };
        apps = input.apps.${system} or { };
      };
      imported = resolver.flake.importInput context input args;
      nativePackages = outputs.legacyPackages // outputs.packages;
    in input // {
      inherit input imported;
      inherit (context) buildConfig;
      builders = imported.builders or input.builders or { };
    } // set.optional isNative {
      inherit system outputs;
    } // set.optional isBuild {
      packages = if useNative then nativePackages else imported;
    };
  };
  util = {
    regex = {
      splitExt = p: s: resolver.util.regex.parseSplit (regex.split p s);

      parseSplit = split: let
        len = list.length split;
        count = len / 2;
        prefix = list.index split 0;
        splits = list.generate (i: let
          captures = list.index split (1 + i * 2);
          suffix = list.index split (2 + i * 2);
        in {
          inherit suffix captures;
        }) count;
        hasSplits = len != 1;
      in {
        inherit split count prefix splits hasSplits;
        suffix = bool.toNullable hasSplits (list.last split);
        strings = [ prefix ] ++ map ({ captures, suffix }: suffix) splits;
      };
    };
  };
}
