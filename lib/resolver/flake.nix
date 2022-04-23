{ self, std }: let
  inherit (std.lib) types set list function bool nullable optional;
  inherit (self.lib)
    BuildConfig System
    CallFlake Context
    FlakeInput FlConfig FlData FlakeType
    InputConfig
    InputOutputs ImportMethod QueryScope
    Offset;
in {
  CallFlake = {
    TypeId = "fl:CallFlake";
    new = {
      inputs
    , buildConfigs
    , config
    , args
    }: {
      type = CallFlake.TypeId;
      inherit inputs buildConfigs config args;
    };

    flOutput = call: {
      inherit (call) config args;
      systems = set.fromList (list.map (bc: {
        _0 = BuildConfig.attrName bc;
        _1 = BuildConfig.serialize bc;
      }) call.buildConfigs);
      import = throw "TODO:flakes/import";
      impure = (CallFlake.flOutput call).import {
        context = Context.new {
          inherit call;
          buildConfig = BuildConfig.Impure;
        };
      };
    };

    flConfig = call: FlConfig.new {
      inherit (call) config;
    };
    args = call: call.args;
    staticContext = call: Context.new { inherit call; };
    nativeContexts = call: set.map (_: Context.byBuildConfig (CallFlake.staticContext call)) (CallFlake.buildConfigs call);
    buildConfigs = call: set.fromList (list.map (bc: { _0 = BuildConfig.attrName bc; _1 = bc; }) call.buildConfigs);
    contextOutputs = call: set.map (_: Context.outputs) (CallFlake.nativeContexts call);
    staticOutputs = call: set.retain FlakeInput.StaticAttrs (Context.outputs (CallFlake.staticContext call));
    filteredNativeOutputs = call: let
      contextOutputs = CallFlake.contextOutputs call;
      packageAttrs = set.retain (FlakeInput.NativeAttrs ++ FlakeInput.FlNativePackageSetAttrs) call.args;
      filterOutput = name: output: let
        available = builtins.tryEval (output.meta.available or true);
      in available.value || !available.success;
      filterOutputs = name: outputs: rec {
        # TODO: how to handle apps and devShells?
        checks = set.filter filterOutput outputs;
        packages = checks; # TODO: consider set.map'ing anything broken into an unbuildable derivation instead
        legacyPackages = builtins.trace "TODO:CallFlake.filteredNativeOutputs/filterOutputs/legacyPackages" packages;
      }.${name} or outputs;
    in set.map (name: _: set.map (system: outputs: filterOutputs name outputs.${name}) contextOutputs) packageAttrs;
    filteredOutputs = call: let
      filteredNativeOutputs = CallFlake.filteredNativeOutputs call;
    in CallFlake.staticOutputs call // filteredNativeOutputs // {
      flakes = CallFlake.flOutput call // set.retain FlakeInput.FlNativePackageSetAttrs filteredNativeOutputs;
    };

    self = call: call.inputs.self or (throw "who am i?");
    flakeInputs = call: call.inputs;
    inputConfigs = call: let
      # TODO: consider whether `self` gets special treatment here or not
      inputConfigs = FlConfig.inputConfigs (CallFlake.flConfig call);
    in set.map (name: _: InputConfig.Default name) call.inputs // inputConfigs;

    filteredInputs = call: let
      inputConfigs = CallFlake.inputConfigs call;
    in set.filter (name: _: FlakeType.isInput (InputConfig.flType inputConfigs.${name})) call.inputs;

    # canonicalizeInputName :: CallFlake -> Optional string
    canonicalizeInputName = call: name: optional.match (set.lookup name call.inputs) {
      just = _: optional.just name;
      nothing = set.lookup name (CallFlake.inputAliases call);
    };

    # inputAliases :: CallFlake -> { string => InputName }
    inputAliases = call: let
      inputConfigs = CallFlake.inputConfigs call;
      aliasPairs = name: inputConfig: list.map (alias: { _0 = alias; _1 = name; }) (InputConfig.aliases inputConfig);
    in set.fromList (list.concat (set.mapToList aliasPairs inputConfigs));

    # allInputNames :: CallFlake -> [InputName]
    allInputNames = call: CallFlake.orderedInputNames call ++ set.keys (CallFlake.inputAliases call);

    # orderedInputNames :: CallFlake -> [InputName]
    orderedInputNames = call:
      list.singleton "self" ++ set.keys (set.without [ "self" ] (CallFlake.filteredInputs call));

    describe = call: FlakeInput.describe (CallFlake.self call);
  };

  FlakeInput = {
    new = {
      input
    }: input;

    __functor = FlakeInput: input: FlakeInput.new {
      inherit input;
    };

    Default = {
      description = "empty flake";
      sourceInfo = { };
      outPath = builtins.placeholder "";
      outputs = {
        flakes = {
          systems = [ ];
          config = {
            name = "<empty>";
            type = FlakeType.Ignore;
          };
        };
      };
    };

    FlOutput = "flakes";
    StaticAttrs = [ "lib" "overlays" "overlay" "nixosModules" "nixosModule" "nixosConfigurations" "templates" "defaultTemplate" ];
    NativeAttrs = FlakeInput.NativePackageAttrs ++ FlakeInput.NativePackageSetAttrs;
    NativePackageAttrs = [ "defaultPackage" "defaultApp" "devShell" ];
    NativePackageSetAttrs = [
      "packages" "legacyPackages"
      "devShells"
      "checks"
      "apps"
    ];
    FlNativeAttrs = FlakeInput.FlNativePackageSetAttrs ++ FlakeInput.FlNativePackageAttrs;
    FlNativePackageSetAttrs = [ "builders" ];
    FlNativePackageAttrs = [ ];

    sourceInfo = fi: fi.sourceInfo;
    outPath = fi: fi.outPath;

    # description :: FlakeInput -> Optional string
    description = set.lookup "description";

    # flConfig :: FlakeInput -> FlConfig
    flConfig = flakeInput: FlConfig.withFlakeInput { inherit flakeInput; };

    # flData :: FlakeInput -> FlData
    flData = flakeInput: bool.toOptional (FlakeInput.isFl flakeInput) (FlData.withFlakeInput { inherit flakeInput; });

    isAvailable = fi: (builtins.tryEval (fi ? sourceInfo)).success;

    isFl = fi: fi ? ${FlakeInput.FlOutput}.systems;

    # hasNative :: FlakeInput -> BuildConfig -> bool
    hasNative = fi: buildConfig: let
      # TODO: configurable comparison strictness?
      systems = FlakeInput.nativeBuildConfigs fi;
    in optional.isJust (list.findIndex (BuildConfig.approxEquals buildConfig) (set.values systems));

    # defaultImportPath :: FlakeInput -> Optional string
    defaultImportPath = fi: let
      defaultPath = "${FlakeInput.outPath fi}/default.nix";
    in bool.toOptional (builtins.pathExists defaultPath) defaultPath;

    # nativeBuildConfigs :: FlakeInput -> { string => BuildConfig }
    nativeBuildConfigs = fi: let
      nativeAttrs' = set.mapToList (_: set.keys) (set.retain FlakeInput.NativeAttrs fi);
      nativeAttrs = set.gen (list.concat nativeAttrs') BuildConfig;
    in optional.match (FlakeInput.flData fi) {
      just = FlData.systems;
      nothing = nativeAttrs;
    };

    # nativeSystemNames :: FlakeInput -> [string]
    nativeSystemNames = fi: set.keys (FlakeInput.nativeBuildConfigs fi);

    staticOutputs = fi: set.without FlakeInput.NativeAttrs fi;

    nativeOutputs = fi: { buildConfig }: let
      nativeBuilders = set.retain FlakeInput.FlNativeAttrs fi.flakes or { };
      nativeAttrs = set.retain FlakeInput.NativeAttrs fi // nativeBuilders;
      error = name: throw "flake input ${FlakeInput.describe fi} is missing output ${name} for ${BuildConfig.describe buildConfig}";
      mapAttr = name: attr: attr.${BuildConfig.localDouble buildConfig} or (error name);
    in set.map mapAttr nativeAttrs;

    outputs = fi: { buildConfig ? null }: let
      nativeOutputs = nullable.match buildConfig {
        just = buildConfig: FlakeInput.nativeOutputs { inherit buildConfig; };
        nothing = { };
      };
    in fi // nativeOutputs;

    describe = fi: let
      name = optional.match (FlConfig.name (FlakeInput.flConfig fi)) {
        just = function.id;
        nothing = "<<FlakeInput>>";
      };
      desc = optional.match (FlakeInput.description fi) {
        just = desc: "(${desc})";
        nothing = "";
      };
    in name + desc;
  };

  InputOutputs = {
    TypeId = "fl:InputOutputs";
    new = {
      flakeInput
    , inputConfig
    , context
    , importMethod ? null
    }: {
      type = InputOutputs.TypeId;
      inherit flakeInput inputConfig context;
      importMethod = nullable.match importMethod {
        just = function.id;
        nothing = ImportMethod.select {
          inherit inputConfig flakeInput;
          inherit (context) buildConfig;
        };
      };
    };

    outputs = io: InputOutputs.Importer.${io.importMethod} {
      inherit (io) flakeInput inputConfig context;
    };

    # TODO: merge a list of InputOutputs
    pkgs = io: let
      outputs = InputOutputs.outputs io;
    in InputOutputs.MergeScopes [
      outputs.packages or { }
      outputs.builders or { }
      outputs.legacyPackages or { }
    ];

    lib = io: let
      outputs = InputOutputs.outputs io;
    in outputs.lib or { };

    namespacedPkgs = io: InputOutputs.wrapNamespace io QueryScope.Packages (InputOutputs.pkgs io);
    namespacedLib = io: InputOutputs.wrapNamespace io QueryScope.Lib (InputOutputs.lib io);
    wrapNamespace = io: scope: target: let
      namespace = {
        ${QueryScope.Packages} = optional.match (InputConfig.pkgsNamespace io.inputConfig) {
          just = function.id;
          nothing = FlConfig.pkgsNamespace (FlakeInput.flConfig io.flakeInput);
        };
        ${QueryScope.Lib} = optional.match (InputConfig.libNamespace io.inputConfig) {
          just = function.id;
          nothing = FlConfig.libNamespace (FlakeInput.flConfig io.flakeInput);
        };
      }.${scope} or (throw "Unknown namespace scope ${toString scope}");
    in set.assignAt namespace target { };

    describe = io: let
      buildConfig = nullable.match io.buildConfig or null {
        just = bc: ".${BuildConfig.describe bc}";
        nothing = "";
      };
    in "${InputConfig.inputName io.inputConfig}.outputs/${io.importMethod}${buildConfig}";

    Importer = {
      # TODO: make these attrs lazy, also expose `extraOutputs` for unknown attrs
      ${ImportMethod.DefaultImport} = { flakeInput, inputConfig, context }: let
      in throw "TODO:Importer.DefaultImport of ${InputConfig.inputName inputConfig}";

      ${ImportMethod.FlImport} = { flakeInput, inputConfig, context }: let
      in throw "TODO:Importer.FlImport of ${InputConfig.inputName inputConfig}";

      ${ImportMethod.Native} = { flakeInput, inputConfig, context }: let
        system = BuildConfig.localDouble context.buildConfig;
      in flakeInput // FlakeInput.nativeOutputs flakeInput { inherit (context) buildConfig; };

      ${ImportMethod.Pure} = { flakeInput, inputConfig, context }: let
      in FlakeInput.staticOutputs flakeInput;

      ${ImportMethod.Self} = { flakeInput, inputConfig, context }: let
      in flakeInput // Context.outputs context;
    };

    # TODO: recursive merges
    MergeScopes = scopes: list.foldl' set.semigroup.append {} (list.reverse scopes);
  };

  ImportMethod = {
    DefaultImport = "default.nix";
    FlImport = "flakes.import";
    Native = "localSystem";
    Pure = "pure";
    Self = "self";

    Default = ImportMethod.Native;

    supportsInput = importMethod: { flakeInput, inputConfig, buildConfig ? null }: let
      flType = InputConfig.flType inputConfig;
      eager = InputConfig.eagerEval inputConfig;
      isFlake = FlakeType.isFlake flType;
    in {
      ${ImportMethod.Self} = InputConfig.isSelf inputConfig;
      ${ImportMethod.Pure} = isFlake;
      ${ImportMethod.Native} = isFlake && (buildConfig == null || !eager || FlakeInput.hasNative flakeInput buildConfig);
      ${ImportMethod.FlImport} = flType == FlakeType.Fl || optional.isJust (FlakeInput.flData flakeInput);
      #${ImportMethod.DefaultImport} = optional.isJust (FlakeInput.defaultImportPath flakeInput);
      ${ImportMethod.DefaultImport} = optional.isJust (InputConfig.defaultImport inputConfig);
    }.${importMethod} or false;

    select = {
      flakeInput ? null
    , inputConfig ? null
    , buildConfig ? null
    }: let
      preference = list.singleton ImportMethod.Self ++ (if buildConfig == null then [
        ImportMethod.Pure ImportMethod.DefaultImport
      ] else if BuildConfig.isNative buildConfig then [
        ImportMethod.Native ImportMethod.FlImport ImportMethod.DefaultImport ImportMethod.Pure
      ] else [
        ImportMethod.FlImport ImportMethod.DefaultImport ImportMethod.Pure
      ]);
      first = list.findIndex (importMethod: nullable.match inputConfig {
        just = inputConfig: ImportMethod.supportsInput importMethod {
          inherit inputConfig flakeInput buildConfig;
        };
        nothing = true;
      }) preference;
      input'desc = nullable.match inputConfig {
        just = InputConfig.inputName;
        nothing = InputConfig.UnknownName;
      };
      bc'desc = nullable.match buildConfig {
        just = bc: ".${BuildConfig.describe bc}";
        nothing = "";
      };
    in optional.match first {
      nothing = throw "Failed to select ImportMethod for ${input'desc}${bc'desc}";
      just = list.index preference;
    };
  };

  QueryScope = {
    Packages = "packages";
    Lib = "lib";

    Default = QueryScope.Packages;
  };

  FlData = {
    TypeId = "fl:FlData";
    new = {
      data
    }: {
      type = FlData.TypeId;
      inherit data;
    };

    withFlakeInput = {
      flakeInput
    }: FlConfig.new {
      config = flakeInput.${FlakeInput.FlOutput} or { };
    };

    # data :: FlData -> set
    data = fd: fd.data;

    # config :: FlData -> FlConfig
    config = fd: FlConfig.new {
      config = (FlData.data fd).config or { };
    };

    # systems :: FlData -> { string => BuildConfig }
    systems = fd: set.map (_: BuildConfig) (FlData.data fd).systems;
  };

  FlConfig = {
    TypeId = "fl:FlConfig";
    new = {
      config
    }: {
      type = FlConfig.TypeId;
      inherit config;
    };

    withFlakeInput = {
      flakeInput
    }: FlConfig.new {
      config = flakeInput.${FlakeInput.FlOutput}.config or { };
    };

    __functor = FlConfig: config: FlConfig.new {
      inherit config;
    };

    # configData :: FlConfig -> set
    configData = fc: fc.config;

    # name :: FlConfig -> Optional string
    name = fc: set.lookup "name" (FlConfig.configData fc);

    # flType :: FlConfig -> Optional FlakeType
    flType = fc: set.lookup "type" (FlConfig.configData fc);

    # inputConfigs :: FlConfig -> { string => InputConfig }
    inputConfigs = fc: set.map (name: config: InputConfig.new {
      inherit name config;
    }) (FlConfig.configData fc).inputs or { };

    # libNamespace :: FlConfig -> [string]
    libNamespace = fc: let
      default = optional.match (FlConfig.name fc) {
        just = list.singleton;
        nothing = [ ];
      };
    in set.atOr default [ "lib" "namespace" ] (FlConfig.configData fc);

    # pkgsNamespace :: FlConfig -> [string]
    pkgsNamespace = fc: set.atOr [ ] [ "packages" "namespace" ] (FlConfig.configData fc);

    # defaultImport :: FlConfig -> Optional import
    defaultImport = fc: set.lookupAt [ "import" ImportMethod.DefaultImport ] (FlConfig.configData fc);

    callArgs = fc: (FlConfig.configData fc).call or { };
    callArgsFor = fc: attr: (FlConfig.callArgs fc).${attr} or { };
  };

  FlakeType = {
    Fl = "fl"; # generated by flakelib
    Flake = "flake";
    Source = "src";
    Lib = "lib";
    Ignore = "ignore";
    ConfigV0 = "config0";

    # isInput :: FlakeType -> bool
    isInput = flakeType: {
      ${FlakeType.Flake} = true;
      ${FlakeType.Fl} = true;
      ${FlakeType.Lib} = true;
    }.${flakeType} or false;

    # isFlake :: FlakeType -> bool
    isFlake = flakeType: {
      ${FlakeType.Source} = false;
      ${FlakeType.Ignore} = false;
    }.${flakeType} or true;

    Default = FlakeType.Flake;
  };

  InputConfig = {
    TypeId = "fl:InputConfig";
    new = { name, config ? { } }: {
      type = InputConfig.TypeId;
      inherit name config;
    };

    __functor = InputConfig: name: config: InputConfig.new {
      inherit name config;
    };

    Default = name: InputConfig.new { inherit name; };

    # AllInputConfigs :: inputs -> {InputConfig}
    AllInputConfigs = { self, ...}@inputs: set.map (name: _: InputConfig.new {
      inherit name;
      config = self.flakes.config.inputs.${name} or { };
    }) inputs;

    inputName = inputConfig: inputConfig.name;
    configData = inputConfig: inputConfig.config;

    # isSelf :: InputConfig -> bool
    isSelf = inputConfig: inputConfig.name == "self";

    # flType :: InputConfig -> FlakeType
    flType = inputConfig: inputConfig.config.type or FlakeType.Default;

    # importArgs :: InputConfig -> set
    importArgs = inputConfig: inputConfig.config.args or { };

    # importMethod :: InputConfig -> Optional ImportMethod
    importMethod = inputConfig: optional.fromNullable (inputConfig.config.importMethod or null);

    # isNative :: InputConfig -> bool
    isNative = inputConfig: InputConfig.importArgs inputConfig == { };

    # aliases :: InputConfig -> [string]
    aliases = inputConfig: inputConfig.config.aliases or [ ];

    # libNamespace :: InputConfig -> Optional [string]
    libNamespace = inputConfig: set.lookupAt [ "lib" "namespace" ] inputConfig.config;

    # pkgsNamespace :: InputConfig -> Optional [string]
    pkgsNamespace = inputConfig: set.lookupAt [ "packages" "namespace" ] inputConfig.config;

    # defaultImport :: InputConfig -> Optional import
    defaultImport = inputConfig: set.lookupAt [ "import" ImportMethod.DefaultImport ] inputConfig.config;

    # eagerEval :: InputConfig -> bool
    eagerEval = inputConfig: InputConfig.isSelf inputConfig || {
      #${FlakeType.Flake} = true;
      ${FlakeType.Lib} = true;
      ${FlakeType.ConfigV0} = true;
    }.${InputConfig.flType inputConfig} or false;

    UnknownName = "<<UnknownInput>>";
  };

  BuildConfig = {
    TypeId = "fl:BuildConfig";
    new = {
      localSystem
    , crossSystem ? null
    , name ? null
    }: {
      type = BuildConfig.TypeId;
      localSystem = System localSystem;
      crossSystem = nullable.functor.map System crossSystem;
      inherit name;
    };

    __functor = BuildConfig: arg:
      if BuildConfig.check arg then arg
      else if arg ? localSystem then BuildConfig.new arg
      else BuildConfig.Native arg;

    Native = localSystem: BuildConfig.new { inherit localSystem; };

    Impure = nullable.match builtins.currentSystem or null {
      just = localSystem: BuildConfig.new {
        inherit localSystem;
      };
      nothing = throw "BuildConfig.Impure cannot be used in pure evaluation";
    };

    localSystem = bc: bc.localSystem;
    crossSystem = bc: optional.fromNullable bc.crossSystem;

    isNative = bc: bc.crossSystem == null;

    localDouble = bc: System.double bc.localSystem;
    crossDouble = bc: nullable.functor.map System.double bc.crossSystem;

    nativeSystem = bc: bool.toOptional (BuildConfig.isNative bc) bc.localSystem;
    buildSystem = BuildConfig.localSystem;

    hostSystem = bc: nullable.match bc.crossSystem {
      just = function.id;
      nothing = bc.localSystem;
    };
    hostDouble = bc: System.double (BuildConfig.hostSystem bc);

    approxEquals = bc: rhs: BuildConfig.localDouble bc == BuildConfig.localDouble rhs && BuildConfig.crossDouble bc == BuildConfig.crossDouble rhs;

    attrName = bc: let
      local = System.attrName bc.localSystem;
    in nullable.match bc.name {
      just = function.id;
      nothing = nullable.match bc.crossSystem {
        just = crossSystem: "${System.attrName crossSystem}/${local}";
        nothing = local;
      };
    };

    byOffset = bc: offset: {
      ${Offset.None} = bc;
      ${Offset.Build} = BuildConfig.new {
        inherit (bc) localSystem;
      };
      ${Offset.Target} = BuildConfig.new {
        localSystem = bc.crossSystem;
      };
    }.${offset};

    serialize = bc: let
      localSystem = System.serialize bc.localSystem;
    in nullable.match bc.crossSystem {
      just = cross: {
        inherit localSystem;
        crossSystem = System.serialize bc.crossSystem;
      };
      nothing = localSystem;
    };

    check = bc: bc.type or null == BuildConfig.TypeId;
    describe = bc: let
      local = System.describe bc.localSystem;
      cross = System.describe bc.crossSystem;
    in if BuildConfig.isNative bc then local else "${cross}:${local}";
  };

  System = {
    TypeId = "fl:System";
    new = { system, ... }@sys: {
      type = System.TypeId;
      system = sys;
    };

    withDouble = system: System.new {
      inherit system;
    };

    __functor = System: system:
      if System.check system then system
      else if types.string.check system then System.withDouble system
      else System.new system;

    double = system: system.system.system;
    isSimple = system: true; # TODO: actually decide this somehow!

    attrName = system: System.double system;

    serialize = system: if System.isSimple system
      then System.double system
      else system.system;

    #elaborate = lib.systems.elaborate;

    check = system: system.type or null == System.TypeId;
    describe = system: if System.isSimple system
      then System.double system
      else throw "TODO";
  };
}
