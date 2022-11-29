{ self, std }: let
  source = p: import p { inherit self; };
in {
  Std = std.lib // {
    System = std.lib.System // self.lib.Fl.".ext.Std".System;
    Flake = std.lib.Flake // {
      Outputs = std.lib.Flake.Outputs // self.lib.Fl.".ext.Std".Flake.Outputs;
    };
    BuildConfig = std.lib.BuildConfig or { } // self.lib.BuildConfig;
  };

  BuildConfig = source ./buildconfig.nix;
  inherit (self.lib.Std) System;

  Fl = source ./fl // {
    ".ext.Std" = {
      System = source ./system.nix;
      Flake.Outputs = source ./outputs.nix;
    };
  };

  callFlake = source ./callflake.nix;
}
