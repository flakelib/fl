{ self, std }: let
  inherit (std.lib) Ty Rec;
  inherit (self.lib.Fl) Injectable Context Callable;
in Rec.Def {
  name = "fl:Injectable";
  Self = Injectable;
  fields = {
    item.type = Ty.any;
    context.type = Context.TypeId.ty;
    callable.type = Callable.TypeId.ty;
  };
  fn.result = inj: inj.item;
} // {
  Parse = context: item: Injectable.TypeId.new {
    # TODO: do things like splicing and customization here?
    inherit context item;
  };
}
