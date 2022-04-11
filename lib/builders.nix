{
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

  checkCommand = { shellCommand }: {
    command
  , message ? "failed check ${name}"
  , name ? "check"
  , ...
  }@args: let
    extraArgs = removeAttrs args [ "command" "message" ];
  in shellCommand (extraArgs // {
    inherit name;
    checkCommand = command;
    checkMessage = message;
    passAsFile = args.passAsFile or [ ] ++ [ "checkCommand" ];
    command = ''
      docheck() {
        source $checkCommandPath
      }

      if ! docheck; then
        printf "%s\n" "$checkMessage" >&2
        exit 1
      else
        printf "" > $out
      fi
    '';
  });

  checkAssert = { shellCommand }: {
    cond
  , message ? "failed assertion ${name}"
  , name ? "assertion"
  , build ? true
  , tryEval ? true
  , ...
  }@args: let
    extraArgs = removeAttrs args [ "message" "build" "cond" "tryEval" ];
    evaluatedCond = if tryEval
      then (builtins.tryEval cond).value # NOTE: relies on the fact that `value == false` if `success == false`
      else cond;
    cmd = shellCommand (extraArgs // {
      inherit name;
      command = if evaluatedCond
        then ''printf "" > $out''
        else ''printf %s "$message" >&2; exit 1'';
      ${if cond then null else "message"} = message;
    });
  in if ! build && ! evaluatedCond then throw message else cmd;

  shellCommand = { buildConfig }: let
    bc' = buildConfig;
    fn = {
      system ? buildConfig.localSystem.system or (throw "system must be supplied")
    , buildConfig ? bc'
    , command
    , pname ? "shell"
    , version ? null
    , name ? "${pname}${if version != null then "-${version}" else ""}"
    , args ? [ "-e" "-u" ] ++ (
      if arg'asFile then [ "-c" "source $commandPath" ]
      else if arg'toFile then [ (builtins.toFile name command) ]
      else [ "-c" command ])
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
  in fn;

  runCommand = { shellCommand }: let
    fn = name: args: command: shellCommand ({
      inherit name command;
    } // args);
  in fn;
}
