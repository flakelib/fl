{ self, std }@inputs: {
  System = import ./system.nix inputs;

  inherit (import ./resolver/context.nix inputs)
    Context ScopedContext;

  inherit (import ./resolver/flake.nix inputs)
    BuildConfig
    FlakeInput FlConfig FlData FlakeType
    InputConfig FlakeImporters
    CallFlake InputOutputs ImportMethod QueryScope;

  inherit (import ./resolver/resolver.nix inputs)
    Callable ArgDesc Offset;

  inherit (import ./resolver/util.nix inputs)
    Regex;

  callFlake = import ./callflake.nix inputs;
}
