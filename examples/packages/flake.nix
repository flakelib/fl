{
  description = "example flake";
  inputs = {
    flakelib = {
      url = "github:flakelib/fl";
      inputs.std.follows = "std";
    };
    std.url = "github:flakelib/std";
    nixpkgs = { };
  };
  outputs = { flakelib, ... }@inputs: flakelib {
    inherit inputs;
    config = {
      name = "example";
    };

    # you can also inhibit or customize the default behaviour by making the output a function
    # (the default behaviour is equivalent to `packages = { callPackageSet }: callPackageSet packages { }`)
    packages = { callPackages, lib }: lib.Fn.flip callPackages { } {
      # callPackage resolves arguments from the flake's inputs
      # `pkgs` and `lib` are special arguments that merge all inputs into a combined scope
      hello-wrapper = { writeShellScriptBin, hello, lib }: writeShellScriptBin "hello-wrapper" ''
        exec ${lib.Drv.mainProgram hello} -g example "$@"
      '';
      # the hello-wrapper argument is resolved from the definition above
      hello-reference = { writeShellScriptBin, hello-wrapper, lib'Drv'mainProgram }: writeShellScriptBin "hello-reference" ''
        exec ${lib'Drv'mainProgram hello-wrapper} "$@"
      '';
    };
    legacyPackages = {
      # inputs can be explicitly specified in case of naming conflicts
      hello-qualified = { nixpkgs'writeShellScriptBin, nixpkgs'hello, std'lib'Drv'mainProgram }: nixpkgs'writeShellScriptBin "hello-wrapper" ''
        exec ${std'lib'Drv'mainProgram nixpkgs'hello} -g qualified "$@"
      '';
    };
  } // {
    some.static.output = "example";
  };
}
