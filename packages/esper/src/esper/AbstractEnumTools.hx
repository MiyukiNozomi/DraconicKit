package esper;

import haxe.macro.Context;
import haxe.macro.Expr;

class AbstractEnumTools {
	public static macro function toName(e:Expr):Expr {
		var type = Context.typeof(e);
		switch (Context.follow(type)) {
			case TAbstract(_.get() => ab, _) if (ab.meta.has(":enum")):
				var cases:Array<Case> = [];
				for (field in ab.impl.get().statics.get()) {
					if (field.meta.has(":enum") && field.meta.has(":impl")) {
						var name = field.name;
						cases.push({
							values: [macro $i{ab.name}.$name],
							expr: macro $v{name}
						});
					}
				}
				return {pos: e.pos, expr: ESwitch(e, cases, macro "Unknown")};
			default:
				Context.error("Expected an enum abstract", e.pos);
				return macro "";
		}
	}
}
