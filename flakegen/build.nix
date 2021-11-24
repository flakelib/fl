{ lib, callPackage }: let
  placeholderToken = 1337;
  generate = {
    runCommand
  , nix-check
  , flake, outputs
  }: runCommand "flake.nix" {
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
in {
  generate = { flake }: callPackage generate {
    inherit flake;
    outputs =
      if flake ? outputs.import then ''inputs: import ${flake.outputs.import} inputs''
      else throw "unknown flake output";
  };

  nix-check = callPackage ({ writeShellScriptBin, nix2_4 ? nix, nix }: let
    args = lib.optionals (lib.versionAtLeast nix.version "2.4") [
      "--extra-experimental-features" (lib.concatStringsSep " " [ "nix-command" "flakes" ])
    ] ++ [
      "--no-use-registries"
    ];
  in writeShellScriptBin "nix" ''
    export XDG_CACHE_HOME=$TMPDIR/cache
    export XDG_DATA_HOME=$TMPDIR/data
    export XDG_CONFIG_HOME=$TMPDIR/config
    NIX_CHECK_STORE=''${NIX_CHECK_STORE-$TMPDIR/nix-store}
    if [[ ! -e $NIX_CHECK_STORE ]]; then
      mkdir $NIX_CHECK_STORE
      ln -s $NIX_STORE/* $NIX_CHECK_STORE/
      if [[ -n $out ]]; then
        ln -s $out $NIX_CHECK_STORE/
      fi
    fi
    ARGS=(
      --store "$NIX_CHECK_STORE"
      ${lib.escapeShellArgs args}
    )
    if [[ ! -n ''${outputHash-} ]]; then
      ARGS+=(--offline)
    fi
    exec ${nix}/bin/nix "''${ARGS[@]}" "$@"
  '') { };
}
