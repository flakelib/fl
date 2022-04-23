{
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

  checkCommand = { shellCommand }: {
    command
  , message ? "failed assertion ${name}"
  , name ? "assertion"
  , ...
  }@args: let
  in shellCommand (args // {
    inherit name;
    commandStr = command;
    command = ''
      if eval "$commandStr"; then
        printf "" > $out
      else
        printf %s "$message" >&2
        exit 1
      fi
    '';
  });

  shellCommand = { lib, buildConfig }: let
    inherit (lib) nullable string list set types flakelib;
    inherit (flakelib) BuildConfig;
    bc' = buildConfig;
    fn = {
      system ? nullable.match buildConfig {
        just = BuildConfig.localDouble;
        nothing = throw "system must be supplied";
      }
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
    , PATH ? [ ]
    , arg'crossAware ? arg'targetAware
    , arg'targetAware ? false
    , arg'asFile ? false
    , arg'toFile ? false
    , ...
    }@attrs: let
      crossAware = attrs.arg'crossAware or false;
      targetAware = attrs.arg'targetAware or false;
      localSystem = BuildConfig.localDouble buildConfig;
      crossSystem = BuildConfig.crossDouble buildConfig;
      hasPath = attrs ? PATH;
      references = list.filter types.drv.check (set.values attrs)
        ++ list.optionals (hasPath && builtins.isList PATH) (list.filter types.drv.check PATH);
      mapPathInput = input: "${input.bin or input}/bin"; # TODO: splicing and lib.drv
      path = if builtins.isList attrs.PATH then string.concatSep ":" (list.map mapPathInput PATH) else PATH;
      checkPlatform =
        if meta.platforms == null then true
        else nullable.match buildConfig {
          just = bc: list.elem (BuildConfig.hostDouble bc) meta.platforms;
          nothing = true; # TODO: think about this
        };
      meta = passthru.meta or { } // {
        platforms = passthru.meta.platforms or null;
        broken = passthru.meta.broken or false;
        unsupported = passthru.meta.unsupported or (!checkPlatform);
        available = !meta.broken && !meta.unsupported && list.all (input: input.meta.available or true) references;
      };
      drvArgs = removeAttrs attrs [ "command" "arg'crossAware" "arg'targetAware" "arg'asFile" "arg'toFile" "passthru" ] // {
        inherit name system args builder;
        ${if hasPath then "PATH" else null} = path;
        ${if arg'asFile then "command" else null} = command;
        ${if arg'asFile then "passAsFile" else null} = attrs.passAsFile or [ ] ++ [ "command" ];

        ${if crossAware then "localSystem" else null} = localSystem;
        ${if crossAware then "crossSystem" else null} = crossSystem;
        ${if targetAware then "targetSystem" else null} = buildConfig.targetSystem.system or crossSystem;
        ${if (crossAware || targetAware) && args.__structuredAttrs or false && buildConfig != null then "buildConfig" else null} = {
          ${if crossAware then "crossSystem" else null} = buildConfig.crossSystem.system or null;
          ${if crossAware then "localSystem" else null} = buildConfig.localSystem.system;
          ${if targetAware then "targetSystem" else null} = buildConfig.targetSystem;
        };
      };
    in derivation drvArgs // passthru // {
      inherit meta;
    };
  in fn;

  runShellCommand = { shellCommand }: let
    fn = name: args: command: shellCommand ({
      inherit name command;
    } // args);
  in fn;

  devShell = { shellCommand }: let
  in {
    name ? "devShell"
  , ... }@args: shellCommand ({
    inherit name;
    # TODO: build an environment output like nixexprs/mkShellEnv
    command = "echo devShell cannot be built";
  } // args);
}
