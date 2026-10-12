package ryuu.internal;

import ryuu.Console.Logger;
import haxe.io.Error;
import haxe.Json;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Bytes;
import haxe.io.Path;
import ryuu.http.HttpMessages.HttpResponse;
import haxe.crypto.Sha1;
import ryuu.handling.RequestHandler.RequestEvent;
import ryuu.handling.AbstractHandler;

/***

	Don't worry, production builds will bundle stuff, and this route will only be available in dev builds.

**/
#if dev
class CachedESModule {
	public var hash(default, null):String;

	public var content(default, null):Bytes;
	public var headers(default, null):Map<String, String>;

	public function new(content:String, mimeType:String) {
		this.content = Bytes.ofString(content);
		this.hash = Sha1.encode(content);
		this.headers = ["content-type" => '${mimeType}; charset=utf-8', "etag" => '"${this.hash}"'];
	}
}

class ESModuleRoute extends AbstractHandler {
	private static final MAX_RESOLUTION_DEPTH = 32;

	private var cache:Map<String, CachedESModule>;

	public function new() {
		this.cache = new Map();
	}

	@:keep public function GET(event:RequestEvent) {
		var pathStr = event.params.get("path");
		if (pathStr == null)
			return error(404);

		if (StringTools.startsWith(pathStr, "$lib")) {
			pathStr = FileSystem.absolutePath(Path.join([
				Configuration.WorkingDirectory,
				Configuration.StaticDirectory,
				"@library",
				pathStr.substring(4)
			]));
		}

		var cached = this.cache[pathStr];

		if (cached == null) {
			try {
				var srcCode = File.getContent(pathStr);
				cached = new CachedESModule(JavaScriptTransformer.transform(srcCode, pathStr), "text/javascript");
				this.cache.set(pathStr, cached);
				throw new HttpResponse(200, cached.headers, cached.content);
			} catch (err) {
				if (Std.downcast(err, HttpResponse) != null)
					throw err;
				Logger.debug("Could not resolve import: " + pathStr + " because: ", err);
				trace(err.stack);
				return error(404, "Dependency may not exist as specified.");
			}
		}

		var ifNoneMatch = event.req.getHeader("if-none-match");
		Logger.debug("Received a ifNoneMatch:", ifNoneMatch);
		if (ifNoneMatch == null || ifNoneMatch.indexOf(cached.hash) > -1) {
			// throw new HttpResponse(304, cached.headers);
		}
		throw new HttpResponse(200, cached.headers, cached.content);
	}
}
#end
