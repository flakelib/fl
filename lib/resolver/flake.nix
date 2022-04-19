{ self, std }: let
  inherit (std.lib) types set list function bool nullable optional;
  inherit (self.lib)
    BuildConfig System
    CallFlake Context
    FlakeInput FlConfig FlakeType
    Inputs Input InputConfig
    InputOutputs ImportMethod QueryScope
    Offset;
in {
  Inputs = {
    TypeId = "fl:Inputs";
    new = {
      inputs
    }: {
      type = Inputs.TypeId;
      inherit inputs;
    };

    __functor = Inputs: inputs: Inputs.new {
      inherit inputs;
    };

    # withFlakeInputs :: {FlakeInput} -> Inputs
    withFlakeInputs = { self, ... }@inputs: let
      inputConfigs = InputConfig.AllInputConfigs inputs;
      newInput = name: flakeInput: Input.new {
        inherit flakeInput;
        inputConfig = inputConfigs.${name};
      };
    in Inputs.new {
      inputs = set.map newInput inputs;
    };

    inputs = inputs: inputs.inputs;
    self = inputs: inputs.inputs.self or (throw "who am i?");
    flakeInputs = inputs: set.map (_: Input.flakeInput) inputs.inputs;
    inputConfigs = inputs: set.map (_: Input.inputConfig) inputs.inputs;
    inputOutputs = inputs: { context }: set.map (_: input: InputOutputs.new {
      inherit input context;
      importMethod = optional.toNullable (InputConfig.importMethod (Input.inputConfig input));
    }) (Inputs.filteredInputs inputs);

    filteredInputs = inputs: set.filter (name: input: FlakeType.isInput (InputConfig.flType input.inputConfig)) inputs.inputs;

    # inputLookup :: Inputs -> string -> Optional Input
    inputLookup = inputs: name: let
      lookup = function.flip set.lookup inputs.inputs;
      aliases = set.map (alias: lookup) (Inputs.inputAliases inputs);
    in optional.match (lookup name) {
      inherit (optional) just;
      nothing = optional.match (set.lookup name aliases) {
        inherit (optional) nothing;
        just = function.id;
      };
    };

    # inputLookup :: Inputs -> string -> Input
    inputAt = inputs: name: optional.match (Inputs.inputLookup inputs name) {
      just = function.id;
      nothing = throw "inputs.${name} not found in ${Inputs.describe inputs}";
    };

    # inputAliases :: Inputs -> { string => InputName }
    inputAliases = inputs: let
      inputConfigs = Inputs.inputConfigs inputs;
      aliasPairs = name: inputConfig: list.map (alias: { _0 = alias; _1 = name; }) (InputConfig.aliases inputConfig);
    in set.fromList (list.concat (set.mapToList aliasPairs inputConfigs));

    # allInputNames :: Inputs -> [InputName]
    inputNames = inputs: Inputs.orderedInputNames inputs ++ set.keys (Inputs.inputAliases inputs);

    # orderedInputNames :: Inputs -> [InputName]
    orderedInputNames = inputs:
      list.singleton "self" ++ set.keys (set.without [ "self" ] inputs.inputs);

    # orderedInputs :: Inputs -> [Input]
    orderedInputs = inputs: list.map (name: Inputs.inputAt inputs) (Inputs.orderedInputNames inputs);

    describe = inputs: Input.describe (Inputs.self inputs);
  };

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

    flData = inputs: optional.match (FlakeInput.flData (Input.flakeInput (Inputs.self inputs))) {
      just = function.id;
      nothing = throw "inputs.self.flakes not found";
    };
    args = call: call.args;
    staticContext = call: Context.new { inherit call; };
    nativeContexts = call: set.map (_: Context.byBuildConfig (CallFlake.staticContext call)) (CallFlake.buildConfigs call);
    buildConfigs = call: set.fromList (list.map (bc: { _0 = BuildConfig.attrName bc; _1 = bc; }) call.buildConfigs);
    contextOutputs = call: set.map (_: Context.outputs) (CallFlake.nativeContexts call);
    nativeOutputs = call: let
      contextOutputs = CallFlake.contextOutputs call;
      packageAttrs = set.retain (FlakeInput.NativeAttrs ++ FlakeInput.FlNativePackageSetAttrs) call.args;
    in set.map (name: _: set.map (system: outputs: outputs.${name}) contextOutputs) packageAttrs;
    staticOutputs = call: set.retain FlakeInput.StaticAttrs (Context.outputs (CallFlake.staticContext call));
    outputs = call: let
      nativeOutputs = CallFlake.nativeOutputs call;
    in CallFlake.staticOutputs call // nativeOutputs // {
      flakes = CallFlake.flOutput call // set.retain FlakeInput.FlNativePackageSetAttrs nativeOutputs;
    };
    filteredOutputs = call: builtins.trace "TODO:CallFlake.filteredOutputs" CallFlake.outputs call;
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

    # flData :: FlakeInput -> Optional set
    flData = set.lookup FlakeInput.FlOutput;

    # flConfig :: FlakeInput -> FlConfig
    flConfig = flakeInput: FlConfig.new { inherit flakeInput; };

    isAvailable = fi: (builtins.tryEval (fi ? sourceInfo)).success;

    isFl = fi: fi ? ${FlakeInput.FlOutput}.systems;

    # hasNative :: FlakeInput -> BuildConfig -> bool
    hasNative = fi: buildConfig: let
      flConfig = FlakeInput.flConfig fi;
      systems = FlakeInput.nativeSystems fi;
      system = BuildConfig.localDouble buildConfig;
    in optional.isJust (list.findIndex (sys: system == sys) systems);

    # defaultImportPath :: FlakeInput -> Optional string
    defaultImportPath = fi: let
      defaultPath = "${FlakeInput.outPath fi}/default.nix";
    in bool.toOptional (builtins.pathExists defaultPath) defaultPath;

    # flImport :: FlakeInput -> Optional import
    flImport = set.lookupAt [ FlakeInput.FlOutput "import" ];

    # nativeSystems :: FlakeInput -> [string]
    nativeSystems = fi: let
      nativeAttrs' = set.mapToList (_: set.keys) (set.retain FlakeInput.NativeAttrs fi);
      nativeAttrs = set.gen (list.concat nativeAttrs') function.id;
    in if FlakeInput.isFl fi then FlConfig.systems (FlakeInput.flConfig fi)
    else set.keys nativeAttrs;

    # importMethod :: FlakeInput -> Optional ImportMethod
    importMethod = fi: optional.match (FlakeInput.flImport fi) {
      just = _: optional.just ImportMethod.FlImport;
      nothing = optional.match (FlakeInput.defaultImportPath fi) {
        inherit (optional) nothing;
        just = _: optional.just ImportMethod.DefaultImport;
      };
    };

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

  Input = {
    TypeId = "fl:Input";
    new = {
      flakeInput
    , inputConfig
    }: {
      type = Input.TypeId;
      inherit flakeInput inputConfig;
    };

    __functor = Input: flakeInput: Input.new {
      inherit flakeInput;
      inputConfig = InputConfig.Default InputConfig.UnknownName;
    };

    flakeInput = input: input.flakeInput;
    inputConfig = input: input.inputConfig;

    # displayName :: Input -> string
    displayName = input: let
      inputName = InputConfig.inputName input.inputConfig;
      configName = FlConfig.name (FlakeInput.flConfig input.flakeInput);
    in if InputConfig.eagerEval input.inputConfig || inputName == InputConfig.UnknownName
      then optional.match configName {
        just = function.id;
        nothing = inputName;
      } else inputName;

    supportsImportMethod = input: { importMethod, buildConfig ? null }: let
      flType = InputConfig.flType input.inputConfig;
      eager = InputConfig.eagerEval input.inputConfig;
      isFlake = FlakeType.isFlake flType;
    in {
      ${ImportMethod.Self} = InputConfig.isSelf input.inputConfig;
      ${ImportMethod.Pure} = isFlake;
      ${ImportMethod.Native} = isFlake && (buildConfig == null || !eager || FlakeInput.hasNative input.flakeInput buildConfig);
      ${ImportMethod.FlImport} = flType == FlakeType.Fl || optional.isJust (FlakeInput.flImport input.flakeInput);
      #${ImportMethod.DefaultImport} = optional.isJust (FlakeInput.defaultImportPath input.flakeInput);
      ${ImportMethod.DefaultImport} = optional.isJust (InputConfig.defaultImport input.inputConfig);
    }.${importMethod} or false;

    /* TODO newInput = flake: context: OldInput.new {
      inherit flake context;
    };*/

    describe = input: let
      inputName = InputConfig.inputName input.inputConfig;
      name = Input.displayName input;
    in if inputName != name then "${inputName}/${name}" else inputName;
  };

  InputOutputs = {
    TypeId = "fl:InputOutputs";
    new = {
      input
    , context
    , importMethod ? null
    }: {
      type = InputOutputs.TypeId;
      inherit input context;
      importMethod = nullable.match importMethod {
        just = function.id;
        nothing = ImportMethod.select {
          inherit input;
          inherit (context) buildConfig;
        };
      };
    };

    outputs = io: InputOutputs.Importer.${io.importMethod} {
      inherit (io) input context;
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
      inputConfig = Input.inputConfig io.input;
      namespace = {
        ${QueryScope.Packages} = optional.match (InputConfig.pkgsNamespace inputConfig) {
          just = function.id;
          nothing = FlConfig.pkgsNamespace (FlakeInput.flConfig io.input.flakeInput);
        };
        ${QueryScope.Lib} = optional.match (InputConfig.libNamespace inputConfig) {
          just = function.id;
          nothing = FlConfig.libNamespace (FlakeInput.flConfig io.input.flakeInput);
        };
      }.${scope} or (throw "Unknown namespace scope ${toString scope}");
    in set.assignAt namespace target { };

    describe = io: let
      input = Input.describe io.input;
      buildConfig = nullable.match io.buildConfig or null {
        just = bc: ".${BuildConfig.describe bc}";
        nothing = "";
      };
    in "${input}.outputs/${io.importMethod}${buildConfig}";

    Importer = {
      # TODO: make these attrs lazy, also expose `extraOutputs` for unknown attrs
      ${ImportMethod.DefaultImport} = { input, context }: let
        outputs = Input.flakeInput input;
      in throw "TODO:Importer.DefaultImport of ${Input.describe input}";

      ${ImportMethod.FlImport} = { input, context }: let
        outputs = Input.flakeInput input;
      in throw "TODO:Importer.FlImport of ${Input.describe input}";

      ${ImportMethod.Native} = { input, context }: let
        system = BuildConfig.localDouble context.buildConfig;
        outputs = Input.flakeInput input;
      in outputs // FlakeInput.nativeOutputs outputs { inherit (context) buildConfig; };

      ${ImportMethod.Pure} = { input, context }: let
        outputs = Input.flakeInput input;
      in FlakeInput.staticOutputs outputs;

      ${ImportMethod.Self} = { input, context }: let
        outputs = Input.flakeInput input;
      in outputs // Context.outputs context;
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

    select = {
      input ? null
    , buildConfig ? null
    }: let
      preference = list.singleton ImportMethod.Self ++ (if buildConfig == null then [
        ImportMethod.Pure ImportMethod.DefaultImport
      ] else if BuildConfig.isNative buildConfig then [
        ImportMethod.Native ImportMethod.FlImport ImportMethod.DefaultImport ImportMethod.Pure
      ] else [
        ImportMethod.FlImport ImportMethod.DefaultImport ImportMethod.Pure
      ]);
      first = list.findIndex (importMethod: nullable.match input {
        just = input: Input.supportsImportMethod input {
          inherit importMethod buildConfig;
        };
        nothing = true;
      }) preference;
      input'desc = nullable.match input {
        just = Input.describe;
        nothing = "";
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

  FlConfig = {
    TypeId = "fl:FlConfig";
    new = {
      flakeInput
    }: {
      type = FlConfig.TypeId;
      inherit flakeInput;
    };

    __functor = FlConfig: flakeInput: FlConfig.new {
      inherit flakeInput;
    };

    # flakeInput :: FlConfig -> FlakeInput
    flakeInput = fc: fc.flakeInput;

    # data :: FlConfig -> set
    data = fc: fc.flakeInput.${FlakeInput.FlOutput};

    # systems :: FlConfig -> [string]
    systems = fc: (FlConfig.data fc).systems;

    # configData :: FlConfig -> set
    configData = fc: fc.flakeInput.${FlakeInput.FlOutput}.config or { };

    # name :: FlConfig -> Optional string
    name = fc: set.lookup "name" (FlConfig.configData fc);

    # flType :: FlConfig -> Optional FlakeType
    flType = fc: set.lookup "type" (FlConfig.configData fc);

    # libNamespace :: FlConfig -> [string]
    libNamespace = fc: let
      default = optional.match (FlConfig.name fc) {
        just = list.singleton;
        nothing = [ ];
      };
    in set.atOr default [ "lib" "namespace" ] (FlConfig.configData fc.flakeInput);

    # pkgsNamespace :: FlConfig -> [string]
    pkgsNamespace = fc: set.atOr [ ] [ "packages" "namespace" ] (FlConfig.configData fc.flakeInput);

    # defaultImport :: FlConfig -> Optional import
    defaultImport = fc: set.lookupAt [ "import" ImportMethod.DefaultImport ] (FlConfig.configData fc.flakeInput);

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
