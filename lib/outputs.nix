{ self, std }@inputs: let
  inherit (std.lib) List Set Fn Null Opt;
  inherit (self.lib) Fl BuildConfig;
  Outputs = std.lib.Flake.Outputs // self.lib.Flake.Outputs;
in {
  Default = {
    description = "empty flake";
    sourceInfo = { };
    outPath = builtins.placeholder "";
    outputs = {
      flakes = {
        systems = [ ];
        config = {
          name = "<empty>";
          type = Fl.Type.Ignore;
        };
      };
    };
  };

  FlNativeAttrs = Outputs.FlNativePackageSetAttrs ++ Outputs.FlNativePackageAttrs;
  FlNativePackageSetAttrs = [ "builders" ];
  FlNativePackageAttrs = [ ];

  # flConfig :: Outputs -> Fl.Config
  flConfig = flakeInput: Fl.Config.WithOutputs flakeInput;

  # flData :: Outputs -> Optional Fl.Data
  flData = flakeInput: Opt.Iif (Outputs.isFl flakeInput) (Fl.Data.WithOutputs flakeInput);

  isFl = fi: fi ? ${Fl.Data.OutputName}.systems;

  # hasNative :: Outputs -> BuildConfig -> bool
  hasNative = fi: buildConfig: let
    # TODO: configurable comparison strictness?
    systems = Outputs.nativeBuildConfigs fi;
  in Opt.isJust (List.findIndex (BuildConfig.approxEquals buildConfig) (Set.values systems));

  # defaultImportPath :: Outputs -> Optional string
  defaultImportPath = fi: let
    defaultPath = "${Outputs.outPath fi}/default.nix";
  in Opt.Iif (builtins.pathExists defaultPath) defaultPath;

  # nativeBuildConfigs :: Outputs -> { string => BuildConfig }
  nativeBuildConfigs = fi: let
    nativeAttrs' = Set.mapToList (_: Set.keys) (Set.retain Outputs.NativeAttrs fi);
    nativeAttrs = Set.gen (List.concat nativeAttrs') BuildConfig;
  in Opt.match (Outputs.flData fi) {
    just = Fl.Data.systems;
    nothing = nativeAttrs;
  };

  # nativeSystemNames :: Outputs -> [string]
  nativeSystemNames = fi: Set.keys (Outputs.nativeBuildConfigs fi);

  nativeOutputs = fi: { buildConfig }: let
    nativeBuilders = Set.retain Outputs.FlNativeAttrs fi.flakes.outputs or { };
    nativeAttrs = Set.retain Outputs.NativeAttrs fi // nativeBuilders;
    error = name: throw "flake input ${Outputs.show fi} is missing output ${name} for ${BuildConfig.show buildConfig}";
    mapAttr = name: attr: attr.${BuildConfig.attrName buildConfig} or (error name);
  in Set.map mapAttr nativeAttrs;

  outputs = fi: { buildConfig ? null }: let
    nativeOutputs = Null.match buildConfig {
      just = buildConfig: Outputs.nativeOutputs fi { inherit buildConfig; };
      nothing = { };
    };
  in fi // nativeOutputs;

  show = fi: let
    name = Opt.match (Fl.Config.name (Outputs.flConfig fi)) {
      just = Fn.id;
      nothing = "«Flake.Outputs»";
    };
    desc = Opt.match (Outputs.description fi) {
      just = desc: "(${desc})";
      nothing = "";
    };
  in name + desc;
}
