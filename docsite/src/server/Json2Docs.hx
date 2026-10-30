package server;

import haxe.io.Error;
import haxe.io.Path;
import haxe.rtti.CType.TypeTree;
import js.node.Buffer;
import js.node.http.IncomingMessage;
import js.node.http.ServerResponse;
import server.HTML.HTMLTransformer;

using StringTools;

private typedef TypeInfo = {path:String, isPrivate:Bool};

class Json2Docs {
	static final ROOT_PACKAGE = "shinku";
	static final ROUTE_PREFIX = "/apiref";

	final mappings = new Map<String, Array<TypeTree>>();
	final subPackages = new Map<String, Array<String>>();
	final classList:Dynamic = {};

	public function new() {
		final xml = Xml.parse(sys.io.File.getContent("../bin/shinku.xml")).firstElement();
		if (xml == null)
			throw Error.Custom("Couldn't parse ../bin/shinku.xml!");

		final rtti = new haxe.rtti.XmlParser();
		rtti.process(xml, "unused");

		for (child in rtti.root)
			traverse(child);

		for (_ => children in subPackages)
			children.sort((a, b) -> Reflect.compare(a, b));

		for (pack => types in mappings) {
			types.sort((a, b) -> Reflect.compare(shortName(infoOf(a).path), shortName(infoOf(b).path)));
			Reflect.setField(classList, pack, types.map(t -> shortName(infoOf(t).path)));
		}
	}

	static function infoOf(t:TypeTree):TypeInfo {
		return switch t {
			case TTypedecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TClassdecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TEnumdecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TAbstractdecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TPackage(_, fullPath, _): {path: fullPath, isPrivate: true};
		}
	}

	static inline function shortName(path:String)
		return path.substring(path.lastIndexOf('.') + 1);

	static inline function packageOf(path:String) {
		final i = path.lastIndexOf('.');
		return i < 0 ? "" : path.substring(0, i);
	}

	static function describe(t:TypeTree):Dynamic {
		return switch t {
			case TClassdecl(c): {type: "class", data: c};
			case TEnumdecl(c): {type: "enum", data: c};
			case TTypedecl(c): {type: "typedef", data: c};
			case TAbstractdecl(c): {type: "abstract class", data: c};
			case TPackage(_, full, subs): {type: "package", data: {path: full, subs: subs.map(v -> describe(v))}};
		}
	}

	function traverse(node:TypeTree) {
		switch node {
			case TPackage(_, _, subs):
				for (c in subs)
					traverse(c);
			default:
				final info = infoOf(node);
				if (info.isPrivate || !(info.path == ROOT_PACKAGE || info.path.startsWith(ROOT_PACKAGE + ".")))
					return;

				final key = packageOf(info.path);
				var arr = mappings.get(key);
				if (arr == null)
					mappings.set(key, arr = []);
				arr.push(node);
				registerPackage(key);
		}
	}

	function registerPackage(pack:String) {
		var cur = pack;
		while (cur.length > 0) {
			final parent = packageOf(cur);
			var arr = subPackages.get(parent);
			if (arr == null)
				subPackages.set(parent, arr = []);
			if (arr.contains(cur))
				break;
			arr.push(cur);
			cur = parent;
		}
	}

	inline function packageExists(pack:String)
		return mappings.exists(pack) || subPackages.exists(pack);

	function buildPackage(full:String):TypeTree {
		final subs:Array<TypeTree> = [];
		for (child in subPackages.get(full) ?? [])
			subs.push(buildPackage(child));
		for (t in mappings.get(full) ?? [])
			subs.push(t);
		return TPackage(shortName(full), full, subs);
	}

	function findType(pack:String, name:String):Null<TypeTree> {
		for (t in mappings.get(pack) ?? [])
			if (shortName(infoOf(t).path) == name)
				return t;
		return null;
	}

	function serveHTML(thisURL:String, filePath:String, props:Dynamic, req:IncomingMessage, res:ServerResponse) {
		try {
			final body = HTMLTransformer.transformHTML(thisURL, filePath, [
				"hmr" => (elm, ch, turl) -> {
					if (Main.IS_BUILD_MODE)
						elm.remove();
					else
						elm.replaceWith(NodeHtmlParser.parse('<script hmr>${Main.HMR_SCRIPT}</script>'));
				}
			], null, props).toString();

			res.writeHead(200, {
				"Content-Type": "text/html",
				"Content-Length": Std.string(Buffer.byteLength(body)),
				"Cache-Control": "no-store",
			});
			res.end(req.method == "HEAD" ? null : body);
		} catch (e) {
			trace('SSR failure for $thisURL: $e');
			res.writeHead(500, {"Content-Type": "text/plain"});
			res.end("Internal server error"); // don't leak internals to the client
		}
	}

	public function handle(thisURL:String, filePath:String, req:IncomingMessage, res:ServerResponse) {
		final route = Path.withoutExtension(thisURL.substring(ROUTE_PREFIX.length))
			.split('/')
			.filter(v -> v.length > 0)
			.join('.');

		if (route.length == 0) {
			serveHTML(thisURL, Path.join([Main.SERVE_DIRECTORY, "res/html/apiref/index.html"]), {classList: classList}, req, res);
			return;
		}

		final lastDot = route.lastIndexOf('.');
		final targetName = route.substring(lastDot + 1);
		final packageName = lastDot < 0 ? "" : route.substring(0, lastDot);

		var target = findType(packageName, targetName);

		if (target == null && packageExists(route))
			target = buildPackage(route);

		if (target == null) {
			res.writeHead(404, {"Content-Type": "text/plain"});
			res.end("not found");
			return;
		}

		serveHTML(thisURL, Path.join([Main.SERVE_DIRECTORY, "res/html/apiref/class-view.html"]), {target: describe(target), classList: classList}, req, res);
	}
}
