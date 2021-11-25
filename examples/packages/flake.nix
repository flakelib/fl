{
  description = "example flake structure";
  inputs = {
    flakeslib.url = "../../lib";
    nixpkgs.url = "nixpkgs";
  };
  outputs = { flakeslib, ... }@inputs: flakeslib {
    inherit inputs;

    packages = {
      hello-wrapper = { writeShellScriptBin, hello, lib'mainProgram }: writeShellScriptBin "hello-wrapper" ''
        exec ${lib'mainProgram hello} -g example "$@"
      '';
      hello-reference = { writeShellScriptBin, hello-wrapper, lib'mainProgram }: writeShellScriptBin "hello-reference" ''
        exec ${lib'mainProgram hello-wrapper} "$@"
      '';
      hello-qualified = { nixpkgs'writeShellScriptBin, nixpkgs'hello, flakeslib'lib'mainProgram }: nixpkgs'writeShellScriptBin "hello-wrapper" ''
        exec ${flakeslib'lib'mainProgram nixpkgs'hello} -g qualified "$@"
      '';
    };
    some.static.output = "example";
  } // {
    another.static.output = "example";
  };
}
