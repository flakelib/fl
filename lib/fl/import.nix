{ self, std }@inputs: let
  inherit (std.lib) Enum List Null Opt;
  inherit (self.lib) Fl BuildConfig;
  inherit (Fl) ImportMethod;
  Outputs = std.lib.Flake.Outputs // self.lib.Flake.Outputs;
in Enum.Def {
  name = "fl:Fl.ImportMethod";
  Self = ImportMethod;
  var = {
    DefaultImport = "default.nix";
    FlImport = "flakes.import";
    Native = "localSystem";
    Pure = "pure";
    Self = "self";
  };
} // {
  Default = ImportMethod.Native;

  supportsInput = importMethod: { outputs, inputConfig, buildConfig ? null }: let
    flType = Fl.Config.Input.flType inputConfig;
    eager = Fl.Config.Input.eagerEval inputConfig;
    isFlake = Fl.Type.isFlake flType;
  in {
    ${ImportMethod.Self} = Fl.Config.Input.isSelf inputConfig;
    ${ImportMethod.Pure} = isFlake;
    ${ImportMethod.Native} = isFlake && (buildConfig == null || Outputs.hasNative outputs buildConfig);
    ${ImportMethod.FlImport} = flType == Fl.Type.Fl || Opt.isJust (Outputs.flData outputs);
    #${ImportMethod.DefaultImport} = Opt.isJust (Outputs.defaultImportPath outputs);
    ${ImportMethod.DefaultImport} = Opt.isJust (Fl.Config.Input.defaultImport inputConfig);
  }.${importMethod} or false;

  select = {
    outputs ? null
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
        inherit inputConfig outputs buildConfig;
      };
      nothing = true;
    }) preference;
    input'desc = Null.match inputConfig {
      just = Fl.Config.Input.inputName;
      nothing = Fl.Config.Input.UnknownName;
    };
    bc'desc = Null.match buildConfig {
      just = bc: ".${BuildConfig.show bc}";
      nothing = "";
    };
  in Opt.match first {
    nothing = throw "Failed to select ImportMethod for ${input'desc}${bc'desc}";
    just = List.index preference;
  };

  import = importMethod: {
    outputs
  , inputConfig
  , buildConfig ? null
  }: {
    ${ImportMethod.DefaultImport} = (Fl.Config.Input.defaultImport inputConfig).value {
      inherit outputs inputConfig buildConfig;
    };

    # TODO: inputConfig should be able to shape the Desc/Context in some way
    ${ImportMethod.FlImport} = outputs.${Fl.Data.OutputName}.import {
      inherit buildConfig;
    };

    # TODO: inputConfig should shape buildConfig resolution in some way
    ${ImportMethod.Native} = Outputs.outputs outputs {
      inherit buildConfig;
    };

    ${ImportMethod.Pure} = Outputs.staticOutputs outputs;
  }.${importMethod} or (throw "fl:ImportMethod.import: unknown method ${importMethod}");
}
