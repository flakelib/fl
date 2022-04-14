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
