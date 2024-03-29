{ self }@inputs: let
  inherit (self.lib.Std)
    Flake BuildConfig
    Rec Enum Ty List Set Fn Bool Null Opt;
  inherit (Flake) Outputs;
  inherit (self.lib)
    Context
    Fl
    FlakeImporters;
  inherit (Fl) ImportMethod;
in {
  Desc = import ./desc.nix inputs;
  Context = import ./context.nix inputs;
  Defaults = import ./defaults.nix inputs;
  Callable = import ./callable.nix inputs;
  Injectable = import ./injectable.nix inputs;
  InputOutputs = import ./io.nix inputs;
  ImportMethod = import ./import.nix inputs;

  Type = Enum.Def {
    name = "fl:Fl.Type";
    Self = Fl.Type;
    var = {
      Fl = "fl"; # generated by flakelib
      Flake = "flake";
      Source = "src";
      Lib = "lib";
      Ignore = "ignore";
      ConfigV0 = "config0";
    };
  } // {
    # isInput :: Fl.Type -> bool
    isInput = flakeType: {
      ${Fl.Type.Flake} = true;
      ${Fl.Type.Fl} = true;
      ${Fl.Type.Lib} = true;
    }.${flakeType} or false;

    # isFlake :: Fl.Type -> bool
    isFlake = flakeType: {
      ${Fl.Type.Source} = false;
      ${Fl.Type.Ignore} = false;
    }.${flakeType} or true;

    Default = Fl.Type.Flake;
  };

  Data = Rec.Def {
    name = "fl:Fl.Data";
    Self = Fl.Data;
    fields.data.type = Ty.attrs;
    coerce.${Ty.attrs.name} = Fl.Config.New;

    # data :: Fl.Data -> set
    fn.data = fd: fd.data;

    # config :: Fl.Data -> Fl.Config
    fn.config = fd: Fl.Config.new {
      config = (Fl.Data.data fd).config or { };
    };

    # systems :: Fl.Data -> { string => BuildConfig }
    fn.systems = fd: Set.map (_: BuildConfig) (Fl.Data.data fd).systems;
  } // {
    New = data: Fl.Data.TypeId.new {
      inherit data;
    };

    WithOutputs = o: Fl.Data.New o.${Fl.Data.OutputName} or { };

    OutputName = "flakes";
  };

  Config = Rec.Def {
    name = "fl:Fl.Config";
    Self = Fl.Config;
    fields.config.type = Ty.attrs;
    coerce.${Ty.attrs.name} = Fl.Config.New;

    # configData :: Fl.Config -> set
    fn.configData = fc: fc.config;

    # name :: Fl.Config -> Optional string
    fn.name = fc: Set.lookup "name" (Fl.Config.configData fc);

    # flType :: Fl.Config -> Optional Fl.Type
    fn.flType = fc: Set.lookup "type" (Fl.Config.configData fc);

    # inputConfigs :: Fl.Config -> { string => Fl.Config.Input }
    fn.inputConfigs = fc: Set.map (name: config: Fl.Config.Input.New {
      inherit name config;
    }) (Fl.Config.configData fc).inputs or { };

    # libNamespace :: Fl.Config -> [string]
    fn.libNamespace = fc: let
      default = Opt.match (Fl.Config.name fc) {
        just = List.One;
        nothing = [ ];
      };
      ns = Set.atOr default [ "lib" "namespace" ] (Fl.Config.configData fc);
    in List.From ns;

    # pkgsNamespace :: Fl.Config -> [string]
    fn.pkgsNamespace = fc: let
      ns = Set.atOr [ ] [ "packages" "namespace" ] (Fl.Config.configData fc);
    in List.From ns;

    # defaultImport :: Fl.Config -> Optional import
    fn.defaultImport = fc: Set.lookupAt [ "import" ImportMethod.DefaultImport ] (Fl.Config.configData fc);

    fn.callArgs = fc: (Fl.Config.configData fc).call or { };
    fn.callArgsFor = fc: attr: (Fl.Config.callArgs fc).${attr} or { };
  } // {
    New = config: Fl.Config.TypeId.new {
      inherit config;
    };

    WithOutputs = o: Fl.Config.New o.${Fl.Data.OutputName}.config or { };

    Input = Rec.Def {
      name = "fl:Fl.Config.Input";
      Self = Fl.Config.Input;
      fields = {
        name.type = Ty.string;
        config.type = Ty.attrs;
      };

      fn.inputName = inputConfig: inputConfig.name;
      fn.configData = inputConfig: inputConfig.config;

      # isSelf :: Fl.Config.Input -> bool
      fn.isSelf = inputConfig: inputConfig.name == "self";

      # flType :: Fl.Config.Input -> Fl.Type
      fn.flType = inputConfig: inputConfig.config.type or Fl.Type.Default;

      # importArgs :: Fl.Config.Input -> set
      fn.importArgs = inputConfig: inputConfig.config.args or { };

      # importMethod :: Fl.Config.Input -> Optional ImportMethod
      fn.importMethod = inputConfig: Opt.fromNullable (inputConfig.config.importMethod or null);

      # isNative :: Fl.Config.Input -> bool
      fn.isNative = inputConfig: Fl.Config.Input.importArgs inputConfig == { };

      # aliases :: Fl.Config.Input -> [string]
      fn.aliases = inputConfig: inputConfig.config.aliases or [ ];

      # libNamespace :: Fl.Config.Input -> Optional [string]
      fn.libNamespace = inputConfig: Set.lookupAt [ "lib" "namespace" ] inputConfig.config;

      # pkgsNamespace :: Fl.Config.Input -> Optional [string]
      fn.pkgsNamespace = inputConfig: Set.lookupAt [ "packages" "namespace" ] inputConfig.config;

      # defaultImport :: Fl.Config.Input -> Optional import
      fn.defaultImport = inputConfig: Set.lookupAt [ "import" ImportMethod.DefaultImport ] inputConfig.config;

      # eagerEval :: Fl.Config.Input -> bool
      fn.eagerEval = inputConfig: Fl.Config.Input.isSelf inputConfig || {
        #${Fl.Type.Flake} = true;
        ${Fl.Type.Lib} = true;
        ${Fl.Type.ConfigV0} = true;
      }.${Fl.Config.Input.flType inputConfig} or false;
    } // {
      New = { name, config ? { } }: Fl.Config.Input.TypeId.new {
        inherit name config;
      };

      Default = name: let
        defaultConfigs = {
          nixpkgs = {
            import.${ImportMethod.DefaultImport} = FlakeImporters.nixpkgs;
          };
        };
      in Fl.Defaults.InputConfigs.${name} or (Fl.Config.Input.New {
        inherit name;
      });

      Unknown = Fl.Config.Input.Default Fl.Config.Input.UnknownName;

      UnknownName = "«UnknownInput»";
    };
  };
}
