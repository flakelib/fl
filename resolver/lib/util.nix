{ self, std }: let
  inherit (std.lib) list;
  inherit (self.lib) util;
in {
  regex = {
    splitExt = p: s: util.regex.parseSplit (regex.split p s);

    parseSplit = split: let
      len = list.length split;
      count = len / 2;
      prefix = list.index split 0;
      splits = list.generate (i: let
        captures = list.index split (1 + i * 2);
        suffix = list.index split (2 + i * 2);
      in {
        inherit suffix captures;
      }) count;
      hasSplits = len != 1;
    in {
      inherit split count prefix splits hasSplits;
      suffix = bool.toNullable hasSplits (list.last split);
      strings = [ prefix ] ++ map ({ captures, suffix }: suffix) splits;
    };
  };
}
