{ self, std }@inputs: {
  System = import ./system.nix inputs;
  BuildConfig = import ./buildconfig.nix inputs;

  Fl = import ./fl inputs;
  Flake.Outputs = import ./outputs.nix inputs;

  callFlake = import ./callflake.nix inputs;
}
