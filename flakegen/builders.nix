{
  generate = { runCommand, nix-check, lib }: { flake }: let
    placeholderToken = 1337;
    outputs =
      if flake ? outputs.import then ''inputs: import ${flake.outputs.import} inputs''
      else throw "unknown flake output";
  in runCommand "flake.nix" {
    passAsFile = [ "flake" ];
    nativeBuildInputs = [ nix-check ];
    replacement = outputs;
    inherit placeholderToken;
    flake = builtins.toJSON (removeAttrs flake [ "config" "options" ] // {
      outputs = placeholderToken;
    });
  } ''
    nix eval --impure --expr \
      "(builtins.fromJSON (builtins.readFile $flakePath))" |
      sed -e "s|$placeholderToken|$replacement|" > $out
  '';

  nix-check = { runCommand, nix2_4 ? nix, nix, lib }: let
    args = lib.optionals (lib.versionAtLeast nix.version "2.4") [
      "--extra-experimental-features" (lib.concatStringsSep " " [ "nix-command" "flakes" ])
    ] ++ [
      "--no-use-registries"
    ];
  in runCommand "nix-check" ''
    mkdir -p $out/bin $out/share/nix-check
    cp $envPath $out/share/nix-check/env
    substituteAll $commandNix2Path $out/bin/nix
    for basename in $(cd $nix/bin && echo nix-*); do
      substituteAll $commandNixPath $out/bin/$basename
    done
  '' {
    nix = nix2_4;
    passAsFile = [ "env" "commandNix" "commandNix2" ];
    env = ''
      export XDG_CACHE_HOME=$TMPDIR/cache
      export XDG_DATA_HOME=$TMPDIR/data
      export XDG_CONFIG_HOME=$TMPDIR/config
      NIX_CHECK_STORE=''${NIX_CHECK_STORE-$TMPDIR/nix-store}
      if [[ ! -e $NIX_CHECK_STORE ]]; then
        mkdir $NIX_CHECK_STORE
        ln -s $NIX_STORE/* $NIX_CHECK_STORE/
      fi
    '';
    commandNix = ''
      source @out@/share/nix-check/env
      export NIX_STORE_DIR=$NIX_CHECK_STORE
      exec @nix@/bin/@basename@ "$@"
    '';
    commandNix2 = ''
      source @out@/share/nix-check/env
      ARGS=(
        --store "$NIX_CHECK_STORE"
        ${lib.escapeShellArgs args}
      )
      if [[ ! -n ''${outputHash-} ]]; then
        ARGS+=(--offline)
      fi
      exec @nix@/bin/nix "''${ARGS[@]}" "$@"
    '';
  };
}
