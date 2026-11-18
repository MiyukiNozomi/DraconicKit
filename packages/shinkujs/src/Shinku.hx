import js.html.Console;
import haxe.PosInfos;
import haxe.ds.StringMap;
import shinkujs.HotContext;
import shinkujs.HMRClient;

@:expose
class Shinku {
	static var client = new HMRClient();
	static var hotModules = new StringMap<HotContext>();

	public static function createHMRContext(id:String):HotContext {
		if (!hotModules.exists(id)) {
			hotModules.set(id, new HotContext(client, id));
		}
		return hotModules.get(id);
	}

	static function main() {}

	public static function log(?p:Null<PosInfos>, ...args:Dynamic)
		logImplementation(false, p, args);

	public static function error(?p:Null<PosInfos>, ...args:Dynamic)
		logImplementation(true, p, args);

	public static function debug(?p:Null<PosInfos>, ...args:Dynamic) {
		#if draconicdev
		logImplementation(false, p, args);
		#end
	}

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
