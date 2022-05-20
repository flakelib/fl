{ self, std }: let
  inherit (std.lib) Rec Enum Ty Set Fn Null Opt;
  inherit (self.lib) Fl BuildConfig;
  inherit (Fl) Context InputOutputs;
  inherit (InputOutputs) QueryScope;
  Outputs = std.lib.Flake.Outputs // self.lib.Flake.Outputs;
in Rec.Def {
  name = "fl:Fl.InputOutputs";
  fields = {
    outputsData.type = Ty.attrs;
    inputConfig.type = Fl.Config.Input.TypeId.ty;
    flConfig.type = Fl.Config.TypeId.ty;
  };

  fn.outputs = io: io.outputsData;

  fn.pkgs = io: let
    outputs = InputOutputs.outputs io;
  in InputOutputs.MergeScopes [
    outputs.packages or { }
    outputs.builders or { }
    outputs.legacyPackages or { }
  ];

  fn.lib = io: let
    outputs = InputOutputs.outputs io;
  in outputs.lib or { };

  fn.namespacedPkgs = io: InputOutputs.wrapNamespace io QueryScope.Packages (InputOutputs.pkgs io);
  fn.namespacedLib = io: InputOutputs.wrapNamespace io QueryScope.Lib (InputOutputs.lib io);
  fn.wrapNamespace = io: scope: target: let
    namespace = {
      ${QueryScope.Packages} = Opt.match (Fl.Config.Input.pkgsNamespace io.inputConfig) {
        just = Fn.id;
        nothing = Fl.Config.pkgsNamespace io.flConfig;
      };
      ${QueryScope.Lib} = Opt.match (Fl.Config.Input.libNamespace io.inputConfig) {
        just = Fn.id;
        nothing = Fl.Config.libNamespace io.flConfig;
      };
    }.${scope} or (throw "Unknown namespace scope ${toString scope}");
  in Set.assignAt namespace target { };

  show = io: "${Fl.Config.Input.inputName io.inputConfig}.outputs";
} // {
  New = {
    outputsData
  , inputConfig ? Fl.Config.Input.Unknown
  , flConfig ? Fl.Config.Default
  }: InputOutputs.TypeId.new {
    inherit outputsData inputConfig flConfig;
  };

  Import = {
    outputs
  , inputConfig
  , buildConfig
  , importMethod ? Opt.toNullable (Fl.Config.Input.importMethod inputConfig)
  }: let
    selectedMethod = Null.match importMethod {
      just = Fn.id;
      nothing = Fl.ImportMethod.select {
        inherit inputConfig outputs buildConfig;
      };
    };
  in InputOutputs.New {
    inherit inputConfig;
    flConfig = Outputs.flConfig outputs;
    outputsData = Fl.ImportMethod.import selectedMethod {
      inherit outputs inputConfig buildConfig;
    };
  };

  MergeScopes = scopes: Set.mergeWith {
    mapToSet = path: v:
      if Ty.attrs.check v then Opt.just v
      else if Ty.function.check v then Opt.just (Fn.toSet v)
      else Opt.nothing;
    sets = scopes;
  };

  QueryScope = Enum.Def {
    name = "fl:Fl.InputOutputs.QueryScope";
    var = {
      Packages = "packages";
      Lib = "lib";
    };
  } // {
    Default = QueryScope.Packages;
  };
}
