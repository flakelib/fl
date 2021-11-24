{ weh }: let
  inherit (builtins) split length;
  parseArgName = name: let
    inputRegex = "^nixpkgs|^flakes"; # TODO: generate
    parts = split "(${inputRegex}|)'(build$|target$|)" name;
    fastpath = {
      inherit name;
      input = null;
      offset = null;
      components = [ ];
    };
    result = {
      inherit name;
      input = null;
      offset = null; # TODO: consider instead just making splicing explicit at usage site, like say `jq.__spliced.build`
      # TODO: consider if offset needs to compose with propagated inputs at all
      components = [ ];
    };
  in if length parts == 1 then fastpath else result;

  parseCallable = fn: let
    args = functionArgs fn;
    argNames = attrNames args;
    extraConfig = fn.callConfigMeIdk or { };
  in throw "TODO:parseCallable";

  parseInjectable = context: item: let
    # do things like splicing here
  in builtins.trace "TODO:parseInjectable" item;

  makeCallPackage = config: throw "TODO:makeCallPackage";
in {
}
