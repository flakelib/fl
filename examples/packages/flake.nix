{
  description = "example flake";
  inputs = {
    flakelib = {
      url = "github:flakelib/fl";
      inputs.std.follows = "std";
    };
    std.url = "github:flakelib/std";
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { flakelib, ... }@inputs: flakelib {
    inherit inputs;
    config = {
      name = "example";
    };

    packages = {
      # callPackage resolves arguments from the flake's inputs
      # `pkgs` and `lib` are special arguments that merge all inputs into a combined scope
      hello-wrapper = { writeShellScriptBin, hello, lib }: writeShellScriptBin "hello-wrapper" ''
        exec ${lib.drv.mainProgram hello} -g example "$@"
      '';
      # the hello-wrapper argument is resolved from the definition above
      hello-reference = { writeShellScriptBin, hello-wrapper, lib'drv'mainProgram }: writeShellScriptBin "hello-reference" ''
        exec ${lib'drv'mainProgram hello-wrapper} "$@"
      '';
    };
    # you can also inhibit or customize the default behaviour by making the output a function
    # (the default behaviour is equivalent to `packages = { callPackageSet }: callPackageSet packages { }`)
    legacyPackages = { callPackages, lib }: lib.function.flip callPackages { } {
      # inputs can be explicitly specified in case of naming conflicts
      hello-qualified = { nixpkgs'writeShellScriptBin, nixpkgs'hello, std'lib'drv'mainProgram }: nixpkgs'writeShellScriptBin "hello-wrapper" ''
        exec ${std'lib'drv'mainProgram nixpkgs'hello} -g qualified "$@"
      '';
    };
  } // {
    some.static.output = "example";
  };
}
