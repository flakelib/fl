{ self, std }: let
  inherit (std.lib) Ty List Set Fn Bool Null Opt;
  inherit (self.lib)
    BuildConfig System
    CallFlake Context
    FlakeInput FlConfig FlData FlakeType
    InputConfig FlakeImporters
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
      systems = Set.map (_: BuildConfig.serialize) call.buildConfigs;
      import = { buildConfig }: (CallFlake.self call) // (Context.outputs (Context.byBuildConfig (CallFlake.staticContext call) buildConfig));
      impure = (CallFlake.flOutput call).import {
        context = Context.new {
          inherit call;
          buildConfig = BuildConfig.Impure;
        };
      };
      outputs = CallFlake.outputs call;
    };

    flConfig = call: FlConfig.new {
      inherit (call) config;
    };
    args = call: call.args;
    staticContext = call: Context.new { inherit call; };
    nativeContexts = call: Set.map (_: Context.byBuildConfig (CallFlake.staticContext call)) call.buildConfigs;
    contextOutputs = call: Set.map (_: Context.outputs) (CallFlake.nativeContexts call);
    staticOutputs = call: Set.retain FlakeInput.StaticAttrs (Context.outputs (CallFlake.staticContext call));
    filteredNativeOutputs = call: let
      contextOutputs = CallFlake.contextOutputs call;
      packageAttrs = Set.retain (FlakeInput.NativeAttrs ++ FlakeInput.FlNativePackageSetAttrs) call.args;
      filterOutput = name: output: let
        available = builtins.tryEval (output.meta.available or true);
      in available.value || !available.success;
      filterOutputs = name: outputs: rec {
        # TODO: how to handle apps and devShells?
        checks = Set.filter filterOutput outputs;
        packages = checks; # TODO: consider Set.map'ing anything broken into an unbuildable derivation instead
        legacyPackages = builtins.trace "TODO:CallFlake.filteredNativeOutputs/filterOutputs/legacyPackages" packages;
      }.${name} or outputs;
    in Set.map (name: _: Set.map (system: outputs: filterOutputs name outputs.${name}) contextOutputs) packageAttrs;
    filteredOutputs = call: let
      filteredNativeOutputs = CallFlake.filteredNativeOutputs call;
    in CallFlake.staticOutputs call // filteredNativeOutputs // {
      flakes = CallFlake.flOutput call // Set.retain FlakeInput.FlNativePackageSetAttrs filteredNativeOutputs;
    };
    nativeOutputs = call: let
      contextOutputs = CallFlake.contextOutputs call;
      packageAttrs = Set.retain (FlakeInput.NativeAttrs ++ FlakeInput.FlNativePackageSetAttrs) call.args;
    in Set.map (name: _: Set.map (system: outputs: outputs.${name}) contextOutputs) packageAttrs;
    outputs = call: let
      nativeOutputs = CallFlake.nativeOutputs call;
    in CallFlake.staticOutputs call // nativeOutputs // {
      flakes = CallFlake.flOutput call // Set.retain FlakeInput.FlNativePackageSetAttrs nativeOutputs;
    };

    self = call: call.inputs.self or (throw "who am i?");
    flakeInputs = call: call.inputs;
    inputConfigs = call: let
      # TODO: consider whether `self` gets special treatment here or not
      inputConfigs = FlConfig.inputConfigs (CallFlake.flConfig call);
    in Set.map (name: _: InputConfig.Default name) call.inputs // inputConfigs;

    filteredInputs = call: let
      inputConfigs = CallFlake.inputConfigs call;
    in Set.filter (name: _: FlakeType.isInput (InputConfig.flType inputConfigs.${name})) call.inputs;

    # canonicalizeInputName :: CallFlake -> Optional string
    canonicalizeInputName = call: name: Opt.match (Set.lookup name call.inputs) {
      just = _: Opt.just name;
      nothing = Set.lookup name (CallFlake.inputAliases call);
    };

    # inputAliases :: CallFlake -> { string => InputName }
    inputAliases = call: let
      inputConfigs = CallFlake.inputConfigs call;
      aliasPairs = name: inputConfig: List.map (alias: { _0 = alias; _1 = name; }) (InputConfig.aliases inputConfig);
      selfAlias = Opt.match (FlConfig.name (CallFlake.flConfig call)) {
        just = name: List.One { _0 = name; _1 = "self"; };
        nothing = List.Nil;
      };
    in Set.fromList (List.concat (Set.mapToList aliasPairs inputConfigs) ++ selfAlias);

    # allInputNames :: CallFlake -> [InputName]
    allInputNames = call: CallFlake.orderedInputNames call ++ Set.keys (CallFlake.inputAliases call);

    # orderedInputNames :: CallFlake -> [InputName]
    orderedInputNames = call:
      List.One "self" ++ Set.keys (Set.without [ "self" ] (CallFlake.filteredInputs call));

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
    NativePackageAttrs = [ "defaultPackage" "defaultApp" "devShell" "defaultBundler" ];
    NativePackageSetAttrs = [
      "packages" "legacyPackages"
      "devShells"
      "checks"
      "apps"
      "bundlers"
    ];
    FlNativeAttrs = FlakeInput.FlNativePackageSetAttrs ++ FlakeInput.FlNativePackageAttrs;
    FlNativePackageSetAttrs = [ "builders" ];
    FlNativePackageAttrs = [ ];

    sourceInfo = fi: fi.sourceInfo;
    outPath = fi: fi.outPath;

    # description :: FlakeInput -> Optional string
    description = Set.lookup "description";

    # flConfig :: FlakeInput -> FlConfig
    flConfig = flakeInput: FlConfig.withFlakeInput { inherit flakeInput; };

    # flData :: FlakeInput -> Optional FlData
    flData = flakeInput: Bool.toOptional (FlakeInput.isFl flakeInput) (FlData.withFlakeInput { inherit flakeInput; });

    isAvailable = fi: (builtins.tryEval (fi ? sourceInfo)).success;

    isFl = fi: fi ? ${FlakeInput.FlOutput}.systems;

    # hasNative :: FlakeInput -> BuildConfig -> bool
    hasNative = fi: buildConfig: let
      # TODO: configurable comparison strictness?
      systems = FlakeInput.nativeBuildConfigs fi;
    in Opt.isJust (List.findIndex (BuildConfig.approxEquals buildConfig) (Set.values systems));

    # defaultImportPath :: FlakeInput -> Optional string
    defaultImportPath = fi: let
      defaultPath = "${FlakeInput.outPath fi}/default.nix";
    in Bool.toOptional (builtins.pathExists defaultPath) defaultPath;

    # nativeBuildConfigs :: FlakeInput -> { string => BuildConfig }
    nativeBuildConfigs = fi: let
      nativeAttrs' = Set.mapToList (_: Set.keys) (Set.retain FlakeInput.NativeAttrs fi);
      nativeAttrs = Set.gen (List.concat nativeAttrs') BuildConfig;
    in Opt.match (FlakeInput.flData fi) {
      just = FlData.systems;
      nothing = nativeAttrs;
    };

    # nativeSystemNames :: FlakeInput -> [string]
    nativeSystemNames = fi: Set.keys (FlakeInput.nativeBuildConfigs fi);

    staticOutputs = fi: Set.without FlakeInput.NativeAttrs fi;

    nativeOutputs = fi: { buildConfig }: let
      nativeBuilders = Set.retain FlakeInput.FlNativeAttrs fi.flakes or { };
      nativeAttrs = Set.retain FlakeInput.NativeAttrs fi // nativeBuilders;
      error = name: throw "flake input ${FlakeInput.describe fi} is missing output ${name} for ${BuildConfig.describe buildConfig}";
      mapAttr = name: attr: attr.${BuildConfig.attrName buildConfig} or (error name);
    in Set.map mapAttr nativeAttrs;

    outputs = fi: { buildConfig ? null }: let
      nativeOutputs = Null.match buildConfig {
        just = buildConfig: FlakeInput.nativeOutputs { inherit buildConfig; };
        nothing = { };
      };
    in fi // nativeOutputs;

    describe = fi: let
      name = Opt.match (FlConfig.name (FlakeInput.flConfig fi)) {
        just = Fn.id;
        nothing = "<<FlakeInput>>";
      };
      desc = Opt.match (FlakeInput.description fi) {
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
      importMethod = Null.match importMethod {
        just = Fn.id;
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
        ${QueryScope.Packages} = Opt.match (InputConfig.pkgsNamespace io.inputConfig) {
          just = Fn.id;
          nothing = FlConfig.pkgsNamespace (FlakeInput.flConfig io.flakeInput);
        };
        ${QueryScope.Lib} = Opt.match (InputConfig.libNamespace io.inputConfig) {
          just = Fn.id;
          nothing = FlConfig.libNamespace (FlakeInput.flConfig io.flakeInput);
        };
      }.${scope} or (throw "Unknown namespace scope ${toString scope}");
    in Set.assignAt namespace target { };

    describe = io: let
      buildConfig = Null.match io.buildConfig or null {
        just = bc: ".${BuildConfig.describe bc}";
        nothing = "";
      };
    in "${InputConfig.inputName io.inputConfig}.outputs/${io.importMethod}${buildConfig}";

    Importer = {
      # TODO: make these attrs lazy, also expose `extraOutputs` for unknown attrs
      ${ImportMethod.DefaultImport} = { flakeInput, inputConfig, context }: (InputConfig.defaultImport inputConfig).value {
        inherit flakeInput inputConfig;
        inherit (context) buildConfig;
      };

      # TODO: inputConfig should be able to shape the CallFlake/Context in some way
      ${ImportMethod.FlImport} = { flakeInput, inputConfig, context }: let
      in flakeInput.${FlakeInput.FlOutput}.import { inherit (context) buildConfig; };

      # TODO: inputConfig should shape buildConfig resolution in some way
      ${ImportMethod.Native} = { flakeInput, inputConfig, context }: flakeInput
        // FlakeInput.nativeOutputs flakeInput { inherit (context) buildConfig; };

      ${ImportMethod.Pure} = { flakeInput, inputConfig, context }: FlakeInput.staticOutputs flakeInput;

      ${ImportMethod.Self} = { flakeInput, inputConfig, context }: flakeInput // Context.outputs context;
    };

    MergeScopes = scopes: let
      unmergeable = v: Ty.drv.check v || Fn.isFunctor v; # TODO: who says you can't merge a plain attrset with a derivation or function/functor?
      append = paths: values: let
        mergeUntil = List.findIndex (v: !Ty.attrs.check v || unmergeable v) values;
      in if List.all Ty.attrs.check values && !List.any unmergeable values then merge paths values
      else Opt.match mergeUntil {
        just = i: let
          split = List.splitAt i values;
        in if i > 0
          then merge paths split._0 # TODO: warn of shadowing/override?
          else List.head values;
        nothing = List.head values;
      };
      merge = paths: Set.mapZip (name: append (paths ++ List.One name));
    in merge [] scopes;
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
      ${ImportMethod.Native} = isFlake && (buildConfig == null || FlakeInput.hasNative flakeInput buildConfig);
      ${ImportMethod.FlImport} = flType == FlakeType.Fl || Opt.isJust (FlakeInput.flData flakeInput);
      #${ImportMethod.DefaultImport} = Opt.isJust (FlakeInput.defaultImportPath flakeInput);
      ${ImportMethod.DefaultImport} = Opt.isJust (InputConfig.defaultImport inputConfig);
    }.${importMethod} or false;

    select = {
      flakeInput ? null
    , inputConfig ? null
    , buildConfig ? null
    }: let
      preference = List.One ImportMethod.Self ++ (if buildConfig == null then [
        ImportMethod.Pure ImportMethod.DefaultImport
      ] else [
        ImportMethod.Native ImportMethod.FlImport ImportMethod.DefaultImport ImportMethod.Pure
      ]);
      first = List.findIndex (importMethod: Null.match inputConfig {
        just = inputConfig: ImportMethod.supportsInput importMethod {
          inherit inputConfig flakeInput buildConfig;
        };
        nothing = true;
      }) preference;
      input'desc = Null.match inputConfig {
        just = InputConfig.inputName;
        nothing = InputConfig.UnknownName;
      };
      bc'desc = Null.match buildConfig {
        just = bc: ".${BuildConfig.describe bc}";
        nothing = "";
      };
    in Opt.match first {
      nothing = throw "Failed to select ImportMethod for ${input'desc}${bc'desc}";
      just = List.index preference;
    };
  };

  FlakeImporters = {
    nixpkgs = { flakeInput, buildConfig, ... }: {
      inherit (flakeInput) lib;
      legacyPackages = import (flakeInput.outPath + "/default.nix") rec {
        localSystem = System.serialize (BuildConfig.localSystem buildConfig);
        crossSystem = Opt.match (BuildConfig.crossSystem buildConfig) {
          just = System.serialize;
          nothing = localSystem;
        };
        # TODO: populate from inputConfig in some way
        config = {
          checkMetaRecursively = true;
        };
        overlays = [ ];
        crossOverlays = [ ];
      };
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
    }: FlData.new {
      data = flakeInput.${FlakeInput.FlOutput} or { };
    };

    # data :: FlData -> set
    data = fd: fd.data;

    # config :: FlData -> FlConfig
    config = fd: FlConfig.new {
      config = (FlData.data fd).config or { };
    };

    # systems :: FlData -> { string => BuildConfig }
    systems = fd: Set.map (_: BuildConfig) (FlData.data fd).systems;
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
    name = fc: Set.lookup "name" (FlConfig.configData fc);

    # flType :: FlConfig -> Optional FlakeType
    flType = fc: Set.lookup "type" (FlConfig.configData fc);

    # inputConfigs :: FlConfig -> { string => InputConfig }
    inputConfigs = fc: Set.map (name: config: InputConfig.new {
      inherit name config;
    }) (FlConfig.configData fc).inputs or { };

    # libNamespace :: FlConfig -> [string]
    libNamespace = fc: let
      default = Opt.match (FlConfig.name fc) {
        just = List.One;
        nothing = [ ];
      };
      ns = Set.atOr default [ "lib" "namespace" ] (FlConfig.configData fc);
    in List.From ns;

    # pkgsNamespace :: FlConfig -> [string]
    pkgsNamespace = fc: let
      ns = Set.atOr [ ] [ "packages" "namespace" ] (FlConfig.configData fc);
    in List.From ns;

    # defaultImport :: FlConfig -> Optional import
    defaultImport = fc: Set.lookupAt [ "import" ImportMethod.DefaultImport ] (FlConfig.configData fc);

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

    Default = name: let
      defaultConfigs = {
        nixpkgs = {
          import.${ImportMethod.DefaultImport} = FlakeImporters.nixpkgs;
        };
      };
    in InputConfig.new {
      inherit name;
      config = defaultConfigs.${name} or { };
    };

    inputName = inputConfig: inputConfig.name;
    configData = inputConfig: inputConfig.config;

    # isSelf :: InputConfig -> bool
    isSelf = inputConfig: inputConfig.name == "self";

    # flType :: InputConfig -> FlakeType
    flType = inputConfig: inputConfig.config.type or FlakeType.Default;

    # importArgs :: InputConfig -> set
    importArgs = inputConfig: inputConfig.config.args or { };

    # importMethod :: InputConfig -> Optional ImportMethod
    importMethod = inputConfig: Opt.fromNullable (inputConfig.config.importMethod or null);

    # isNative :: InputConfig -> bool
    isNative = inputConfig: InputConfig.importArgs inputConfig == { };

    # aliases :: InputConfig -> [string]
    aliases = inputConfig: inputConfig.config.aliases or [ ];

    # libNamespace :: InputConfig -> Optional [string]
    libNamespace = inputConfig: Set.lookupAt [ "lib" "namespace" ] inputConfig.config;

    # pkgsNamespace :: InputConfig -> Optional [string]
    pkgsNamespace = inputConfig: Set.lookupAt [ "packages" "namespace" ] inputConfig.config;

    # defaultImport :: InputConfig -> Optional import
    defaultImport = inputConfig: Set.lookupAt [ "import" ImportMethod.DefaultImport ] inputConfig.config;

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
      crossSystem = Null.map System crossSystem;
      inherit name;
    };

    __functor = BuildConfig: arg:
      if BuildConfig.check arg then arg
      else if arg ? localSystem then BuildConfig.new arg
      else BuildConfig.Native arg;

    Native = localSystem: BuildConfig.new { inherit localSystem; };

    Impure = Null.match builtins.currentSystem or null {
      just = localSystem: BuildConfig.new {
        inherit localSystem;
      };
      nothing = throw "BuildConfig.Impure cannot be used in pure evaluation";
    };

    localSystem = bc: bc.localSystem;
    crossSystem = bc: Opt.fromNullable bc.crossSystem;

    isNative = bc: bc.crossSystem == null;

    localDouble = bc: System.double bc.localSystem;
    crossDouble = bc: Null.map System.double bc.crossSystem;

    nativeSystem = bc: Bool.toOptional (BuildConfig.isNative bc) bc.localSystem;
    buildSystem = BuildConfig.localSystem;

    hostSystem = bc: Null.match bc.crossSystem {
      just = Fn.id;
      nothing = bc.localSystem;
    };
    hostDouble = bc: System.double (BuildConfig.hostSystem bc);

    approxEquals = bc: rhs: BuildConfig.localDouble bc == BuildConfig.localDouble rhs && BuildConfig.crossDouble bc == BuildConfig.crossDouble rhs;

    attrName = bc: let
      local = System.attrName bc.localSystem;
    in Null.match bc.name {
      just = Fn.id;
      nothing = Null.match bc.crossSystem {
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
    in Null.match bc.crossSystem {
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
      else if Ty.string.check system then System.withDouble system
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
