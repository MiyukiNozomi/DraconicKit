package server;

import sys.io.File;
import haxe.io.Input;
import haxe.io.Bytes;
import haxe.io.Error;
import shinku.http.HttpMessages.HttpRequest;
import sys.net.Socket;
import shinku.http.HttpSocket;
import shinku.http.HttpMessages.HttpResponse;
import sys.FileSystem;
import server.routes.apiref.APIReferenceRoute.APIReference;
import server.routes.XHTMLRoute;
import haxe.io.Path;
import shinku.std.io.SystemTools;
import sys.thread.Thread;
import shinku.Configuration;
import shinku.std.io.FileWatcher;
import shinku.Console.Logger;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;
import sys.net.Host;
import shinku.http.HttpServer;

using StringTools;

class Main {
	public static var VERSION:Float = Date.now().getTime();

	public static var SERVE_DIRECTORY = "";

	public static var IS_BUILD_MODE = false;

	static function main() {
		SERVE_DIRECTORY = Macros.getServeDirectory();
		Logger.info("Dir: ", SERVE_DIRECTORY);
		Configuration.ShowDebugLogs = false;
		Configuration.StaticDirectory = SERVE_DIRECTORY;

		IS_BUILD_MODE = Sys.args()[0] == "build";

		var sv = new HttpServer(new Host("0.0.0.0"), 3000);

		if (!IS_BUILD_MODE)
			sv.requestHandler.dynamicRouter.addDynamicRoute("/api/reload", new ApiReloadHandler());

		APIReference.init(sv);

		final bump = (reason:String) -> {
			VERSION = Date.now().getTime();
			Logger.warn('[watch] change detected ($reason) -> version $VERSION');
		};

		final handleNewFile = (fp:String) -> {
			if (!fp.endsWith(".xhtml") && !fp.endsWith(".md"))
				return;
			var routename = Path.directory(fp.substring(SERVE_DIRECTORY.length));
			if (!routename.startsWith('/'))
				routename = '/' + routename;

			if (routename.startsWith("/res/html")) {
				Logger.error("Skipped route ", routename, " (cannot host components directly).");
				return;
			}

			sv.requestHandler.dynamicRouter.addDynamicRoute(routename, new XHTMLRoute(fp));
			Logger.warn("New route: ", routename, " added.");
		};
		final handleDeletedFile = (fp:String) -> {
			if (!fp.endsWith(".xhtml") && !fp.endsWith(".md"))
				return;
			var routename = Path.directory(fp.substring(SERVE_DIRECTORY.length));
			if (!routename.startsWith('/'))
				routename = '/' + routename;
			Logger.warn("Route dropped: ", routename, " removed? ", sv.requestHandler.dynamicRouter.removeRouteByName(routename));
		};

		SystemTools.visitDirRecursive(SERVE_DIRECTORY, handleNewFile);

		var watcher = new FileWatcher(SERVE_DIRECTORY, (ev) -> {
			switch (ev) {
				case Added(p):
					handleNewFile(p);
					bump('$p Added');
				case Modified(p): bump('$p Modified');
				case Removed(p):
					handleDeletedFile(p);
					bump('$p Removed');
			}
		});

		if (!IS_BUILD_MODE)
			Thread.create("watcher", () -> {
				Logger.info("Watcher is now running!");
				watcher.run();
			});

		if (IS_BUILD_MODE) {
			var thread = Thread.create("httpServer", () -> sv.start());

			final OUTPUT = "bin/static";
			if (FileSystem.exists(OUTPUT)) {
				Logger.warn("Dir " + OUTPUT + " exists, nuking it.");
				SystemTools.deleteRecursive(OUTPUT);
			}
			FileSystem.createDirectory(OUTPUT);

			var fakeSocket = new HttpSocket(new Socket());

			Logger.info("Server will build the following routes: ");
			for (route in sv.requestHandler.dynamicRouter.routes) {
				var output = Path.join([OUTPUT, route.rawRoutePath]);
				if (!output.endsWith(".xhtml")) {
					output = Path.join([output, "index.xhtml"]);
				}
				Logger.info(" - ", route.rawRoutePath, " -> ", output);

				try {
					sv.requestHandler.handleRequest(fakeSocket, new HttpRequest({
						method: "GET",
						version: "HTTP/1.1",
						target: route.rawRoutePath
					}, []));
				} catch (e:HttpResponse) {
					var value = "no payload was returned.";
					if (e.payload != null) {
						var buffer = Std.downcast(e.payload, Bytes);
						var stream = Std.downcast(e.payload, Input);

						if (buffer != null)
							value = buffer.toString();
						if (stream != null)
							value = stream.readAll().toString();
					}

					if (e.status != 200) {
						throw Error.Custom("Build has failed! reason: " + value);
					}
					trace("Got it! " + e.status + " for " + route.rawRoutePath);
					FileSystem.createDirectory(Path.directory(output));
					File.saveContent(output, value);
				}
			}
			sv.stop();
			Logger.info("XHTML has been transformed and stored. copying resources now..");

			var exclusionDir = Path.join([Main.SERVE_DIRECTORY, "res/html"]);
			SystemTools.visitDirRecursive(Main.SERVE_DIRECTORY, (fp) -> {
				if (fp.startsWith(exclusionDir) || fp.endsWith(".xhtml"))
					return;
				final target = Path.join([OUTPUT, fp.substring(Main.SERVE_DIRECTORY.length)]);
				Logger.info("Copying ", fp, " into ", target);
				FileSystem.createDirectory(Path.directory(target));
				File.copy(fp, target);
			});

			Logger.info("Build complete!");
		} else {
			Logger.info("Server starting with the following routes: ");
			for (route in sv.requestHandler.dynamicRouter.routes) {
				Logger.info(" -", route.rawRoutePath);
			}
			sv.start();
		}
	}
}

class ApiReloadHandler extends AbstractHandler {
	public function GET(event:RequestEvent) {
		return json({
			version: Main.VERSION
		});
	}
}
