{
  description = "example flake structure";
  inputs = {
    flakeslib = {
      url = "../../lib";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        std.follows = "std";
      };
    };
    nixpkgs.url = "nixpkgs";
    std.url = "flakes-std";
  };
  outputs = { flakeslib, ... }@inputs: flakeslib {
    inherit inputs;

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
