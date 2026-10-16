package shinku.internal;

import shinku.internal.interop.Svelte.SvelteBuilder;
import haxe.crypto.Sha1;
import haxe.io.Bytes;
import haxe.io.Path;
import shinku.Console.Logger;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.http.HttpMessages.HttpResponse;
import sys.FileSystem;
import sys.io.File;

/***

	Don't worry, production builds will bundle stuff, and this route will only be available in dev builds.

**/
#if dev
class CachedESModule {
	public var hash(default, null):String;

	public var content(default, null):Bytes;

	public function new(content:String) {
		this.content = Bytes.ofString(content);
		this.hash = Sha1.encode(content);
	}
}

class ESModuleRoute extends AbstractHandler {
	private var cache:Map<String, CachedESModule>;

	public function new() {
		this.cache = new Map();
	}

	private static function getHeaders(etag:String) {
		return ["content-type" => 'text/javascript; charset=utf-8', "etag" => '"${etag}"'];
	}

	@:keep public function GET(event:RequestEvent) {
		var pathStr = event.params.get("path");
		if (pathStr == null)
			return error(404);

		if (StringTools.startsWith(pathStr, "$lib")) {
			pathStr = Path.join(["src/lib", pathStr.substring(4)]);
			if (pathStr == "src/lib") {
				pathStr += "/index.js";
			}
		}

		var ifNoneMatch = event.req.getHeader("if-none-match");

		if (StringTools.endsWith(pathStr, ".svelte")) {
			var component = SvelteBuilder.getComponent(pathStr);
			if (ifNoneMatch == null || ifNoneMatch.indexOf(component.etag) > -1) {
				// throw new HttpResponse(304, ["content-type" => "text/javascript", "etag" => '"${component.etag}"']);
			}

			var script = SvelteBuilder.getComponentScript(component, event.url.pathname, event.url.searchParams);
			return text(script, {
				status: 200,
				headers: getHeaders(component.etag)
			});
		} else {
			var cached = this.cache[pathStr];

			if (cached == null) {
				try {
					var srcCode = File.getContent(pathStr);
					cached = new CachedESModule(JavaScriptTransformer.transform(srcCode, pathStr));
					this.cache.set(pathStr, cached);
					throw new HttpResponse(200, getHeaders(cached.hash), cached.content);
				} catch (err) {
					if (Std.downcast(err, HttpResponse) != null)
						throw err;
					Logger.error("Could not resolve import: " + pathStr + " because: ", err);
					Logger.debug(err.stack);
					return error(404, "Dependency may not exist as specified.");
				}
			}

			if (ifNoneMatch == null || ifNoneMatch.indexOf(cached.hash) > -1) {
				//	throw new HttpResponse(304, getHeaders(cached.hash));
			}
			throw new HttpResponse(200, getHeaders(cached.hash), cached.content);
		}
	}
}
#end
