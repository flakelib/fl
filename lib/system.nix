{ self, std }: let
  System = std.lib.System // self.lib.System;
in {
  Supported = let
    inherit (import ./systems.nix) doubles supported;
    tier1 = supported.tier1;
    tier2 = tier1 ++ supported.tier2;
    tier3 = tier2 ++ supported.tier3;
  in doubles // {
    supported = supported.hydra;
    inherit tier1 tier2 tier3;
  };

  attrName = system: System.double system;
}
