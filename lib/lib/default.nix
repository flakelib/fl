{ self, std }@inputs: {
  supportedSystems = let
    inherit (import ../checks/systems.nix) doubles supported;
    tier1 = supported.tier1;
    tier2 = tier1 ++ supported.tier2;
    tier3 = tier2 ++ supported.tier3;
  in doubles // {
    supported = supported.hydra;
    inherit tier1 tier2 tier3;
  };

  callFlake = import ./callflake.nix inputs;

  resolver = import ./resolver inputs;
}
