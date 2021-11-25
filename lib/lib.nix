{ callPackage }: let
  inherit (builtins) isString mapAttrs intersectAttrs substring baseNameOf;
  fns = {
    # program name as defined by `nix run`
    mainProgramName = drv: let
      withOutPath = (builtins.parseDrvName (
        substring 33 (-1) (baseNameOf (builtins.unsafeDiscardStringContext drv))
      )).name;
      withDrv = drv.meta.mainProgram or drv.pname or (
        builtins.parseDrvName drv.name
      ).name;
    in if drv ? name then withDrv
    else if isString drv then withOutPath
    else throw "unknown program";

    isInput = input: input ? narHash;

    buildConfigWith = {
      system ? throw "must provide either `system` or `localSystem`"
    , localSystem ? { inherit system; }
    , crossSystem ? localSystem
    , isNative ? localSystem == crossSystem
    }: {
      inherit localSystem crossSystem isNative;
    };


    /*importInput = { importInputWith }: input: if ! self'lib.isInput input
    then importInputWith input
    else importInput {
      inherit input;
    };*/
  };
  callfns = {
    supportedSystems = { nixpkgs'lib'systems }: let
      inherit (nixpkgs'lib'systems) doubles supported;
      tier1 = supported.tier1;
      tier2 = tier1 ++ supported.tier2;
      tier3 = tier2 ++ supported.tier3;
    in doubles // {
      supported = supported.hydra;
      inherit tier1 tier2 tier3;
    };
    # absolute path to `drv`'s `mainProgramName`
    mainProgram = { mainProgramName }: drv: "${drv}/bin/${mainProgramName drv}";

    # the opposite of `removeAttrs`
    keepAttrs = { nixpkgs'lib'genAttrs }: attrs: names: intersectAttrs (nixpkgs'lib'genAttrs names (_: null)) attrs;

    buildConfig = { buildConfigWith }: arg:
      if isString arg then buildConfigWith { system = arg; }
      else buildConfigWith arg;

    callWithScope = { nixpkgs'lib'functionArgs }: scope: target: args: let
      implicitArgs = intersectAttrs (nixpkgs'lib'functionArgs target) scope;
    in target (implicitArgs // args);

    importInputWith = { buildConfigWith, callWithScope }: {
      input
    , inputs
    , buildConfig ? buildConfigWith { inherit system; }
    , system ? throw "must provide either `system` or `buildConfig`"
    , ...
    }@args: let
      extraArgs = removeAttrs args [ "input" "inputs" "buildConfig" "system" ];
      importer = import input;
      importArgs = (if buildConfig != null then {
        inherit (buildConfig) localSystem crossSystem;
      } else { }) // inputs;
      imported = callWithScope importArgs importer extraArgs;
    in imported;

    loadInputWith = { buildConfigWith, importInputWith }: {
      input
    , inputs
    , buildConfig ? buildConfigWith { inherit system; }
    , system ? throw "must provide either `system` or `buildConfig`"
    , ...
    }@args: let
      extraArgs = removeAttrs args [ "input" "inputs" "buildConfig" "system" ];
      inherit (buildConfig.localSystem) system;
      hasFlakePackages = input ? legacyPackages.${system} || input ? packages.${system};
      isNative = buildConfig != null && buildConfig.isNative && hasFlakePackages;
      useNativePackages = isNative && extraArgs == { };
      legacyPackages = input.legacyPackages.${system} or { };
      packages = input.packages.${system} or { };
      imported = importInputWith args;
      nativePackages = legacyPackages // packages;
      hasFlakes = input ? flakes.import;
      loaded = input.flakes.import {
        inherit buildConfig;
      };
    in input // {
      inherit input buildConfig;
      ${if isNative then "outputs" else null} = {
        inherit packages legacyPackages;
        checks = input.checks.${system} or { };
        apps = input.apps.${system} or { };
      };
      ${if hasFlakes && loaded ? builders then "builders" else null} = loaded.builders or { };
      import = imported;
      ${if buildConfig != null then "packages" else null} = if useNativePackages then nativePackages
        else if hasFlakes then loaded.legacyPackages or { } // loaded.packages or { }
        else imported;
    };
  };
in mapAttrs (_: fn: callPackage fn { }) callfns // fns
