{ self, std }: let
  inherit (std.lib) Rec Enum Ty List Set Fn Null Opt;
  inherit (self.lib) Fl BuildConfig;
  inherit (Fl) Context InputOutputs;
  inherit (InputOutputs) QueryScope;
  Outputs = std.lib.Flake.Outputs // self.lib.Flake.Outputs;
in Rec.Def {
  name = "fl:Fl.InputOutputs";
  fields = {
    outputs.type = Outputs.TypeId.ty;
    inputConfig.type = Fl.Config.Input.TypeId.ty;
    context.type = Fl.Context.TypeId.ty;
    importMethod.type = Fl.ImportMethod.TypeId.ty;
  };

  fn.outputs = io: InputOutputs.Importer.${io.importMethod} {
    inherit (io) outputs inputConfig context;
  };

  # TODO: merge a list of InputOutputs
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
        nothing = Fl.Config.pkgsNamespace (Outputs.flConfig io.outputs);
      };
      ${QueryScope.Lib} = Opt.match (Fl.Config.Input.libNamespace io.inputConfig) {
        just = Fn.id;
        nothing = Fl.Config.libNamespace (Outputs.flConfig io.outputs);
      };
    }.${scope} or (throw "Unknown namespace scope ${toString scope}");
  in Set.assignAt namespace target { };

  show = io: let
    buildConfig = Null.match io.buildConfig or null {
      just = bc: ".${BuildConfig.show bc}";
      nothing = "";
    };
  in "${Fl.Config.Input.inputName io.inputConfig}.outputs/${io.importMethod}${buildConfig}";
} // {
  New = {
    outputs
  , inputConfig
  , context
  , importMethod ? null
  }: InputOutputs.TypeId.new {
    inherit outputs inputConfig context;
    importMethod = Null.match importMethod {
      just = Fn.id;
      nothing = Fl.ImportMethod.select {
        inherit inputConfig outputs;
        inherit (context) buildConfig;
      };
    };
  };

  MergeScopes = scopes: Set.mergeWith {
    mapToSet = path: v:
      if Ty.attrs.check v then Opt.just v
      else if Ty.function.check v then Opt.just (Fn.toSet v)
      else Opt.nothing;
    sets = scopes;
  };

  Importer = {
    # TODO: make these attrs lazy, also expose `extraOutputs` for unknown attrs
    ${Fl.ImportMethod.DefaultImport} = { outputs, inputConfig, context }: (Fl.Config.Input.defaultImport inputConfig).value {
      inherit outputs inputConfig;
      inherit (context) buildConfig;
    };

    # TODO: inputConfig should be able to shape the Desc/Context in some way
    ${Fl.ImportMethod.FlImport} = { outputs, inputConfig, context }: let
    in outputs.${Fl.Data.OutputName}.import { inherit (context) buildConfig; };

    # TODO: inputConfig should shape buildConfig resolution in some way
    ${Fl.ImportMethod.Native} = { outputs, inputConfig, context }: outputs
      // Outputs.nativeOutputs outputs { inherit (context) buildConfig; };

    ${Fl.ImportMethod.Pure} = { outputs, inputConfig, context }: Outputs.staticOutputs outputs;

    ${Fl.ImportMethod.Self} = { outputs, inputConfig, context }: outputs // Context.outputs context;
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
