{ self, std }: let
  inherit (std.lib) Ty Rec List Set Fn Bool Null Opt;
  inherit (self.lib) BuildConfig Callable;
  inherit (Callable) Offset;
  System = std.lib.System // self.lib.System;
in Rec.Def {
  name = "fl:BuildConfig";
  Self = BuildConfig;
  coerce.${toString System.TypeId} = BuildConfig.Native;
  coerce.${Ty.attrs.name} = BuildConfig.New;
  coerce.${Ty.string.name} = s: BuildConfig.Native (System s);
  fields = {
    name = {
      type = Ty.nullOr Ty.string;
      default = null;
    };
    crossSystem = {
      type = Ty.nullOr System.TypeId.type;
      default = null;
    };
    localSystem.type = System.TypeId.type;
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

  Impure = Null.match builtins.currentSystem or null {
    just = localSystem: BuildConfig.New {
      inherit localSystem;
    };
    nothing = throw "BuildConfig.Impure cannot be used in pure evaluation";
  };
}
