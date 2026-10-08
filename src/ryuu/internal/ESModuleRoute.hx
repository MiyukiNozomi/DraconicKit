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

	private function dash(path:String) {
		return ~/(^|\/)\.\.(?=$|\/)/g.replace(path, "$1__");
	}

	private function undash(path:String) {
		return ~/(^|\/)__(?=$|\/)/g.replace(path, "$1..");
	}

	private function countParentRefs(path:String) {
		var re = ~/(^|\/)\.\.(?=\/|$)/g;
		var count = 0;
		while (re.match(path))
			count++;
		return count;
	}

	private function getPackageName(pathStr:String) {
		var components = pathStr.split('/').filter(v -> v.length > 0);
		var packageName = components[0];

		var freeComponents;
		if (packageName.charAt(0) == '@') {
			if (components.length == 1)
				text("Forbiddden! bad package name: " + pathStr, {status: 403, headers: []});
			packageName += '/' + components[1];
			freeComponents = components.slice(2);
		} else {
			freeComponents = components.slice(1);
		}
		return {packageName: packageName, fragment: (freeComponents.length > 0 ? "./" + freeComponents.join('/') : '.')};
	}

	@:keep public function GET(event:RequestEvent) {
		var pathStr = event.params.get("path");
		if (pathStr == null)
			return error(404);
		pathStr = this.undash(pathStr);

		var cached = this.cache[pathStr];
		if (cached == null) {
			if (pathStr.charAt(0) == '/' || countParentRefs(pathStr) > MAX_RESOLUTION_DEPTH)
				return error(403, "Access is denied.");

			var packageInfo = getPackageName(pathStr);
			try {
				var dependencyFile = Json.parse(File.getContent(Path.join(["node_modules", packageInfo.packageName, "package.json"])));
				var exports = Reflect.getProperty(dependencyFile, "exports");
				var target = Reflect.getProperty(exports, packageInfo.fragment);

				var srcCode = "<error>";
				var rootDir = "<error>";

				if (target == null) {
					var physicalPath = Path.join(["node_modules", packageInfo.packageName, packageInfo.fragment]);
					var successful = false;

					if (FileSystem.exists(physicalPath)) {
						var iJSFile = Path.join([physicalPath, "index.js"]);
						var isDir = false;

						if (FileSystem.isDirectory(physicalPath) && FileSystem.exists(iJSFile)) {
							physicalPath = iJSFile;
							isDir = true;
						}

						srcCode = File.getContent(physicalPath);

						var b = Path.join([packageInfo.packageName, packageInfo.fragment]);
						rootDir = isDir ? b : Path.directory(b);
						successful = true;
					}

					if (!successful) {
						throw Error.Custom("No 'target' for " + packageInfo.fragment + " on package " + packageInfo.packageName);
					}
				} else {
					var defaultVariant = Reflect.getProperty(target, "default");
					var browserVariant = Reflect.getProperty(target, "browser");

					var variantToLoad = browserVariant == null ? defaultVariant : browserVariant;
					if (variantToLoad == null) {
						throw Error.Custom("Target " + packageInfo.fragment + " on package " + packageInfo.packageName
							+ " has no emittable candidate, it's exports are " + Json.stringify(target));
					}

					var resolvedPath = Path.normalize(Path.join(["node_modules", packageInfo.packageName, variantToLoad]));
					srcCode = File.getContent(resolvedPath);
					rootDir = Path.directory(Path.join([packageInfo.packageName, variantToLoad]));
				}

				cached = new CachedESModule(JavaScriptTransformer.transform(srcCode), "text/javascript");
				this.cache.set(pathStr, cached);
				throw new HttpResponse(200, cached.headers, cached.content);
			} catch (err) {
				if (Std.downcast(err, HttpResponse) != null)
					throw err;
				Logger.debug("Could not resolve import: " + pathStr + " because: ", err);
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
