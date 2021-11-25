{ config, lib, ... }: let
  inherit (lib)
    filterAttrs mapAttrs
    mkOption mkIf mkMerge;
  ty = lib.types;
  attrTys = ty.oneOf [ (ty.attrsOf attrTys) ty.str ty.bool ] // {
    description = "attrs";
  };
  inputLocationType = { config, options, ... }: {
    options = {
      url = mkOption {
        type = ty.str;
      };
      type = mkOption {
        type = ty.enum [ "path" "git" "mercurial" "tarball" "github" "gitlab" "indirect" ];
      };
      owner = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
      repo = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
      rev = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
      ref = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
      dir = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
      narHash = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
    };

    config.out.attrs = mkMerge [
      (mkIf options.url.isDefined { inherit (config) url; })
      (mkIf options.type.isDefined (filterAttrs (_: v: v != null) {
        inherit (config) type owner repo rev ref dir narHash;
      }))
    ];
  };
  inputConfigType = { config, options, ... }: {
    options = {
      follows = mkOption {
        type = ty.nullOr ty.str;
        default = null;
      };
      flake = mkOption {
        type = ty.bool;
      };
    };

    config.out.attrs = mkMerge [
      (mkIf (config.follows != null) {
        inherit (config) follows;
      })
      (mkIf options.flake.isDefined {
        inherit (config) flake;
      })
    ];
  };
  inputType = { config, ... }: {
    imports = [ inputLocationType inputConfigType ];

    options = {
      inputs = mkOption {
        type = ty.attrsOf (ty.submodule inputType);
        default = { };
      };

      out.attrs = mkOption {
        type = attrTys;
        default = { };
      };
    };

    config = {
      out.attrs = mkMerge [
        (mkIf (config.inputs != { }) { inputs = mapAttrs (_: input: input.out.attrs) config.inputs; })
      ];
    };
  };
  outputsType = { config, ... }: {
    options = {
      import = mkOption {
        type = ty.str;
      };

      out.attrs = mkOption {
        type = attrTys;
      };
    };

    config.out.attrs = {
      inherit (config) import;
    };
  };
in {
  options = {
    description = mkOption {
      type = ty.nullOr ty.str;
      default = null;
    };

    inputs = mkOption {
      type = ty.attrsOf (ty.submodule inputType);
      default = { };
    };

    outputs = mkOption {
      type = ty.submodule outputsType;
      default = {
        import = "./outputs.nix";
      };
    };

    out.attrs = mkOption {
      type = attrTys;
    };
  };
  config.out.attrs = mkMerge [
    (mkIf (config.description != null) { inherit (config) description; })
    (mkIf (config.inputs != { }) { inputs = mapAttrs (_: input: input.out.attrs) config.inputs; })
    { outputs = config.outputs.out.attrs; }
  ];
}
