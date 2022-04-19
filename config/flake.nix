{
  description = "flakelib overridable configuration";
  outputs = { self, ... }: {
    flakes = {
      config = {
        type = "config0";
        name = "fl-config";
      };
    };
  };
}
