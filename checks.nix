{ checkAssert }: let
in {
  supportedSystems = checkAssert {
    name = "lib.supportedSystems";
    cond = builtins.trace "TODO: inline nixpkgs systems and compare" true;
  };
}
