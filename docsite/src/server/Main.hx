package server;

import haxe.Json;
import haxe.io.Path;
import js.Node;
import js.node.Buffer;
import js.node.Fs;
import js.node.Http;
import js.node.Timers.Timeout;
import js.node.http.IncomingMessage;
import js.node.http.ServerResponse;
import server.HTML.HTMLTransformer;
import shinku.std.MimeTypes;
import shinku.std.URL;
import shinku.std.io.FileWatcher;
import sys.FileSystem;

using StringTools;

class Main {
	static inline var PORT:Int = 3000;
	static inline var POLL_INTERVAL_MS:Int = 500;
	public static var IS_BUILD_MODE = false;

	public static var SERVE_DIRECTORY = "";

	static var HMR_SCRIPT = '(function () { var current = null; function poll() {fetch("/api/reload", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (data) {if (current === null) {current = data.version;} else if (data.version !== current) {location.reload();return;}setTimeout(poll, ${POLL_INTERVAL_MS});}).catch(function () {setTimeout(poll, 1000);});}poll();})();';

	static var version:Float = Date.now().getTime();

	public static var bumpTimer:Null<Timeout>;

	private static function watchTree() {
		final bump = (reason) -> {
			if (bumpTimer != null)
				Node.clearTimeout(bumpTimer);
			bumpTimer = Node.setTimeout(() -> {
				version = Date.now().getTime();
				trace('[watch] change detected ($reason) -> version $version');
			}, 50);
		};

		var watcher = new FileWatcher(SERVE_DIRECTORY, (ev) -> {
			switch (ev) {
				case Added(p): bump('$p Added');
				case Modified(p): bump('$p Modified');
				case Removed(p): bump('$p Removed');
			}
		});

		// mom, can i have threads?
		// no, screw you!
		// ok.. JS is bad.
		Node.setInterval(() -> {
			watcher.tick();
		}, watcher.intervalMs);
	}

	private static function serveFile(thisURL:String, filePath:String, req:IncomingMessage, res:ServerResponse) {
		final send = (status:Int, body:String, type = "text/plain") -> {
			res.writeHead(status, {
				"Content-Type": type,
				"Cache-Control": "no-store",
			});
			res.end(body);
		};

		var exists = FileSystem.exists(filePath);
		if (exists && FileSystem.isDirectory(filePath)) {
			if (FileSystem.exists(Path.join([filePath, "index.md"])))
				return serveFile(thisURL, Path.join([filePath, "index.md"]), req, res);
			return serveFile(thisURL, Path.join([filePath, "index.html"]), req, res);
		} else if (!exists) {
			return send(404, "Not found");
		}

		var type;
		var isMarkdown = false;
		var markdownSrc = "";

		if (filePath.endsWith(".md")) {
			markdownSrc = sys.io.File.getContent(filePath);
			isMarkdown = true;
			type = "text/html";
			filePath = Path.join([SERVE_DIRECTORY, "res/html/markdown.html"]);
		} else {
			type = MimeTypes.forFilename(filePath);
		}

		if (type == "text/html") {
			try {
				final body = HTMLTransformer.transformHTML(thisURL, filePath, [
					"hmr" => (elm, ch, turl) -> {
						if (IS_BUILD_MODE)
							elm.remove();
						else
							elm.replaceWith(NodeHtmlParser.parse('<script hmr>$HMR_SCRIPT</script>'));
					},
					"placeholder" => (elm, ch, turl) -> {
						if (isMarkdown) {
							HTMLTransformer.applyMarkdownFor(elm, markdownSrc);
						}
					}
				]).toString();
				res.writeHead(200, {
					"Content-Type": type,
					"Content-Length": Std.string(Buffer.byteLength(body)),
					"Cache-Control": "no-store",
				});
				return res.end(req.method == "HEAD" ? null : body);
			} catch (e) {
				trace(e);
				return send(500, "SSR Failure! \n" + e.toString());
			}
		}

		res.writeHead(200, {
			"Content-Type": type,
			"Content-Length": Std.string(FileSystem.stat(filePath).size),
			"Cache-Control": "no-store",
		});
		if (req.method == "HEAD")
			return res.end();

		final stream = Fs.createReadStream(filePath);
		stream.on("error", () -> res.destroy());
		stream.pipe(res);
	}

	private static function visitDirImpl(path:String, visit:(fullPath:String) -> Void) {
		if (FileSystem.isDirectory(path)) {
			final entries = FileSystem.readDirectory(path);
			for (entry in entries) {
				visitDirImpl(Path.join([path, entry]), visit);
			}
		} else {
			visit(path);
		}
	}

	public static function visitDirRecursive(directory:String, visit:(fullPath:String) -> Void) {
		var absolute = FileSystem.absolutePath(Path.normalize(directory));
		visitDirImpl(absolute, visit);
	}

	static function main() {
		SERVE_DIRECTORY = Macros.getServeDirectory();
		trace("Serve dir: " + SERVE_DIRECTORY);

		IS_BUILD_MODE = Sys.args()[0] == "build";

		if (!IS_BUILD_MODE)
			watchTree();

		var server = Http.createServer((req, res) -> {
			final send = (status:Int, body:String, type = "text/plain") -> {
				res.writeHead(status, {
					"Content-Type": type,
					"Cache-Control": "no-store",
				});
				res.end(body);
			};

			if (req.method != "GET" && req.method != "HEAD")
				return send(405, "Method Not Allowed");

			var pathname;
			try {
				pathname = new URL(req.url, "http://localhost").pathname;
			} catch (_) {
				return send(400, "Bad Request");
			}

			if (pathname == "/api/reload")
				return send(200, Json.stringify({version: version}), "application/json");

			var servePath = Path.join([SERVE_DIRECTORY, pathname]);
			return serveFile(pathname, servePath, req, res);
		});

		server.listen(PORT, () -> {
			trace('Serving ${SERVE_DIRECTORY}');
			var loc = 'http://localhost:${PORT}';
			trace(loc);

			if (IS_BUILD_MODE) {
				trace("Building website... (you launched it in build mode, server will shutdown after build..");

				final exclusion = Path.join([SERVE_DIRECTORY, "res/html"]);
				final routes = new Map<String, String>();

				visitDirRecursive(SERVE_DIRECTORY, v -> {
					if (v.startsWith(exclusion))
						return;

					var routeName = v.substring(SERVE_DIRECTORY.length);
					var outputDir;
					if (routeName.endsWith("index.md")) {
						routeName = Path.directory(routeName);
						outputDir = Path.join([
							Path.normalize(Path.join([SERVE_DIRECTORY, "../../dist/static", routeName])),
							"index.html"
						]);
					} else {
						outputDir = Path.normalize(Path.join([SERVE_DIRECTORY, "../../dist/static", routeName]));
					}
					routes.set(routeName, outputDir);
				});

				var total = 0;
				for (routeName => outputDir in routes) {
					trace("Request ($total)" + routeName + " will output to " + outputDir);

					var http = new haxe.Http(loc + routeName);
					http.onBytes = (b) -> {
						FileSystem.createDirectory(Path.directory(outputDir));
						sys.io.File.saveBytes(outputDir, b);

						total++;

						if (total == routes.size()) {
							trace("Build Complete!");
							server.close();
						}
					};
					http.request();
				}
			}
		});
	}
}
