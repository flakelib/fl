{ callPackage }: let
  inherit (builtins) isString mapAttrs intersectAttrs;
  fns = {
    # program name as defined by `nix run`
    mainProgramName = drv: drv.meta.mainProgram or drv.pname or (
      builtins.parseDrvName drv.name
    ).name;

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
      importArgs = {
        inherit (buildConfig) localSystem crossSystem;
      } // inputs;
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
      isNative = buildConfig.isNative && hasFlakePackages;
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
      import = imported;
      packages = if useNativePackages then nativePackages
        else if hasFlakes then loaded.legacyPackages or { } // loaded.packages or { }
        else imported;
    };

    makeCas = { runCommand }: {
      drv
    , hashes
    , version ? drv.version
    , mode ? "recursive" # or "flat"
    }: let
      hasHash = hashes ? version;
      hashAttrs = {
        outputHashMode = mode;
        outputHash = hashes.${version};
      };
      casDrv = runCommand "cas" ({
        inherit drv;
      } // hashAttrs) ''
        main() {
          if type -P cp > /dev/null; then
            cp -r $drv $out
            return
          fi

          cp() {
            < "$1" > "$2"
          }

          unimplemented() {
            echo $1 unimplemented >&2
            exit 1
          }

          rec() {
            if [[ -f $drv$1 ]]; then
              if [[ -x $drv$1 ]]; then
                unimplemented executables
              fi
              cp "$drv$1" "$out$1"
            elif [[ -d $drv$1 ]]; then
              mkdir "$out$1"
              for f in $(cd $drv$1 && echo *); do
                rec "$1/$f"
              done
            elif [[ -l $drv$1 ]]; then
              unimplemented symlinks
            else
              echo unknown file "$drv$1" >&2
              exit 1
            fi
          }
          rec ""
        }
        main
      '';
    in if ! hasHash then drv
    else if drv ? overrideAttrs then drv.overrideAttrs hashAttrs
    else drv // casDrv;

    appendCas = { writeShellScriptBin, jq'build }: let
    in writeShellScriptBin "append-cas" ''
      set -eu

      SOURCE_HASHES=$PWD/schema/source-hashes.json
      SOURCE="$1"
      SOURCE_REV="$2"
      SOURCE_HASH=$(nix --extra-experimental-features nix-command hash file --sri "$SOURCE")

      if [[ ! -e "$SOURCE_HASHES" ]]; then
        echo "hashfile does not exist: $SOURCE_HASHES" >&2
        exit 1
      fi

      EXPR=". + { \"$SOURCE_REV\":\"$SOURCE_HASH\" }"

      LOCKFILE=''${XDG_RUNTIME_DIR-/tmp}/base16-update-source.lock
      lock() { flock $1 99; }
      exec 99>$LOCKFILE
      trap 'set +e; lock -u; lock -xn && rm -f $LOCKFILE' EXIT

      lock -xn
      JSON="$(${jq'build}/bin/jq -M --sort-keys "$EXPR" "$SOURCE_HASHES")"
      printf "%s\n" "$JSON" > "$SOURCE_HASHES"
    '';

    checkAssert = { shellCommand }: {
      cond
    , system
    , message
    , name ? "assertion"
    , build ? true
    }: let
      cmd = shellCommand {
        inherit system name;
        command = if cond
          then ''printf "" > $out''
          else ''printf %s "$message" >&2; exit 1'';
        ${if cond then null else "message"} = message;
      };
    in if ! cond && ! build then throw message else cmd;

    shellCommand = { spliceFn }: let
      fn = {
        system ? buildConfig.localSystem.system or (throw "system must be supplied")
      , buildConfig ? null
      , command
      , pname ? "shell"
      , version ? null
      , name ? "${pname}${if version != null then "-${version}" else ""}"
      , args ?
        if arg'asFile then [ "-c" "source $shellCommandPath" ]
        else if arg'toFile then [ (builtins.toFile name command) ]
        else [ "-c" command ]
      , builder ? "/bin/sh"
      , passthru ? { }
      , arg'crossAware ? arg'targetAware
      , arg'targetAware ? false
      , arg'asFile ? false
      , arg'toFile ? false
      , ...
      }@attrs: let
        crossAware = attrs.arg'crossAware or false;
        targetAware = attrs.arg'targetAware or false;
        localSystem = buildConfig.localSystem.system or system;
        crossSystem = buildConfig.crossSystem.system or localSystem;
        drvArgs = removeAttrs attrs [ "command" "arg'crossAware" "arg'targetAware" "arg'asFile" "arg'toFile" "passthru" ] // {
          inherit name system args builder;
          ${if arg'asFile then "command" else null} = command;
          ${if arg'asFile then "passAsFile" else null} = attrs.passAsFile or [ ] ++ [ "command" ];

          ${if crossAware then "localSystem" else null} = localSystem;
          ${if crossAware then "crossSystem" else null} = crossSystem;
          ${if targetAware then "targetSystem" else null} = buildConfig.targetSystem.system or crossSystem;
          ${if (crossAware || targetAware) && args.__structuredAttrs or false && buildConfig != null then "buildConfig" else null} = {
            ${if crossAware then "crossSystem" else null} = buildConfig.crossSystem;
            ${if crossAware then "localSystem" else null} = buildConfig.localSystem;
            ${if targetAware then "targetSystem" else null} = buildConfig.targetSystem;
          };
        };
      in derivation drvArgs // passthru;
      splicer = {
        fn
      , buildConfig
      }: args: let
        args' = {
          # TODO: consider merge approaches if these are specified in `args`
          inherit buildConfig;
          inherit (buildConfig.localSystem) system;
        } // args;
      in fn args';
    in spliceFn {
      inherit fn splicer;
    };

    runCommand = { shellCommand }: let
      fn = name: args: command: shellCommand ({
        inherit name command;
      } // args);
    in fn;
  };
in mapAttrs (_: fn: callPackage fn { }) callfns // fns
