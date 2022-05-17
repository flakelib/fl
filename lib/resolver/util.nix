{ self, std }: let
  inherit (std.lib) List Bool;
  Regex = std.lib.Regex // self.lib.Regex;
in {
  Regex = {
    splitExt = p: s: Regex.parseSplit (Regex.split p s);

    parseSplit = split: let
      len = List.length split;
      count = len / 2;
      prefix = List.index split 0;
      splits = List.generate (i: let
        captures = List.index split (1 + i * 2);
        suffix = List.index split (2 + i * 2);
      in {
        inherit suffix captures;
      }) count;
      hasSplits = len != 1;
    in {
      inherit split count prefix splits hasSplits;
      suffix = Bool.toNullable hasSplits (List.last split);
      strings = [ prefix ] ++ map ({ captures, suffix }: suffix) splits;
    };
  };
}
