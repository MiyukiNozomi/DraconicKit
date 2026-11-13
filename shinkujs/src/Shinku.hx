import js.html.Console;
import haxe.PosInfos;
import shinkujs.ShinkuHotContext;
import haxe.ds.StringMap;

@:expose
class Shinku {
	static var hotModules:StringMap<ShinkuHotContext> = new StringMap();

	public static function createHMRContext(id:String):ShinkuHotContext {
		if (!hotModules.exists(id)) {
			hotModules.set(id, new ShinkuHotContext(id));
		}

		return hotModules.get(id);
	}

	static function main() {}

	public static function log(?p:Null<PosInfos>, ...args:Dynamic)
		logImplementation(false, p, args);

	public static function error(?p:Null<PosInfos>, ...args:Dynamic)
		logImplementation(true, p, args);

	static function logImplementation(isError:Bool, p:Null<PosInfos>, args:Array<Dynamic>) {
		(isError ? Console.error : Console.log)("%cDraconicKit",
			'color:white; background-color:${isError ? 'red' : 'purple'}; padding:2px 4px; border-radius:4px;', args.map(stringify)
			.join(' '));
	}

	static function stringify(v:Dynamic):String {
		if (Std.isOfType(v, haxe.Exception)) {
			var e:haxe.Exception = v;
			return e.details();
		}
		return Std.string(v);
	}
}
