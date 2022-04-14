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
      hello-wrapper = { writeShellScriptBin, hello, lib'drv'mainProgram }: writeShellScriptBin "hello-wrapper" ''
        exec ${lib'drv'mainProgram hello} -g example "$@"
      '';
      hello-reference = { writeShellScriptBin, hello-wrapper, lib'drv'mainProgram }: writeShellScriptBin "hello-reference" ''
        exec ${lib'drv'mainProgram hello-wrapper} "$@"
      '';
      hello-qualified = { nixpkgs'writeShellScriptBin, nixpkgs'hello, std'lib'drv'mainProgram }: nixpkgs'writeShellScriptBin "hello-wrapper" ''
        exec ${std'lib'drv'mainProgram nixpkgs'hello} -g qualified "$@"
      '';
    };
    some.static.output = "example";
  } // {
    another.static.output = "example";
  };
}
