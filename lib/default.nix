{ self, std }@inputs: {
  supportedSystems = let
    inherit (import ./systems.nix) doubles supported;
    tier1 = supported.tier1;
    tier2 = tier1 ++ supported.tier2;
    tier3 = tier2 ++ supported.tier3;
  in doubles // {
    supported = supported.hydra;
    inherit tier1 tier2 tier3;
  };

  inherit (import ./resolver/context.nix inputs)
    Context ScopedContext;

  inherit (import ./resolver/flake.nix inputs)
    BuildConfig System
    FlakeInput FlConfig FlData FlakeType
    InputConfig FlakeImporters
    CallFlake InputOutputs ImportMethod QueryScope;

  inherit (import ./resolver/resolver.nix inputs)
    Callable ArgDesc Offset;

  inherit (import ./resolver/util.nix inputs)
    Regex;

  callFlake = import ./callflake.nix inputs;
}
