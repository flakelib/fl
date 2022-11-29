{ self }: let
  inherit (self.lib.Std) BuildConfig System Ty Rec List Set Fn Bool Null Opt;
  inherit (self.lib) Fl;
  inherit (Fl.Callable) Offset;
in Rec.Def {
  name = "fl:BuildConfig";
  Self = BuildConfig;
  coerce.${toString System.TypeId} = BuildConfig.Native;
  coerce.${Ty.attrs.name} = BuildConfig.Deserialize;
  coerce.${Ty.string.name} = s: BuildConfig.Native (System s);
  fields = {
    name = {
      type = Ty.nullOr Ty.string;
      default = null;
    };
    crossSystem = {
      type = Ty.nullOr System.TypeId.ty;
      default = null;
    };
    localSystem.type = System.TypeId.ty;
  };
  show = bc: let
    local = System.show bc.localSystem;
    cross = System.show bc.crossSystem;
  in if BuildConfig.isNative bc then local else "${cross}:${local}";

  fn.localSystem = bc: bc.localSystem;
  fn.crossSystem = bc: Opt.fromNullable bc.crossSystem;

  fn.isNative = bc: bc.crossSystem == null;

  fn.localDouble = bc: System.double bc.localSystem;
  fn.crossDouble = bc: Null.map System.double bc.crossSystem;

  fn.nativeSystem = bc: Bool.toOptional (BuildConfig.isNative bc) bc.localSystem;
  fn.buildSystem.fn = BuildConfig.localSystem;

  fn.hostSystem = bc: Null.match bc.crossSystem {
    just = Fn.id;
    nothing = bc.localSystem;
  };
  fn.hostDouble = bc: System.double (BuildConfig.hostSystem bc);

  fn.approxEquals = bc: rhs: BuildConfig.localDouble bc == BuildConfig.localDouble rhs && BuildConfig.crossDouble bc == BuildConfig.crossDouble rhs;

  fn.attrName = bc: let
    local = System.attrName bc.localSystem;
  in Null.match bc.name {
    just = Fn.id;
    nothing = Null.match bc.crossSystem {
      just = crossSystem: "${System.attrName crossSystem}/${local}";
      nothing = local;
    };
  };

  fn.byOffset = bc: offset: {
    ${Offset.None} = bc;
    ${Offset.Build} = BuildConfig.New {
      inherit (bc) localSystem;
    };
    ${Offset.Target} = BuildConfig.New {
      localSystem = bc.crossSystem;
    };
  }.${offset};

  fn.serialize = bc: let
    localSystem = System.serialize bc.localSystem;
  in Null.match bc.crossSystem {
    just = cross: {
      inherit localSystem;
      crossSystem = System.serialize bc.crossSystem;
    };
    nothing = localSystem;
  };
} // {
  New = { name ? null, localSystem, crossSystem ? null }: BuildConfig.TypeId.new {
    inherit name crossSystem localSystem;
  };
  Native = localSystem: BuildConfig.New { inherit localSystem; };

  Deserialize = { name ? null, localSystem, crossSystem ? null }: BuildConfig.New {
    inherit name;
    localSystem = System localSystem;
    crossSystem = Null.map System crossSystem;
  };

  Impure = Null.match builtins.currentSystem or null {
    just = localSystem: BuildConfig.New {
      inherit localSystem;
    };
    nothing = _: throw "BuildConfig.Impure cannot be used in pure evaluation";
  };
}
