package server;

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

	static function main() {
		SERVE_DIRECTORY = Macros.getServeDirectory();
		Logger.info("Dir: ", SERVE_DIRECTORY);
		Configuration.ShowDebugLogs = false;
		Configuration.StaticDirectory = SERVE_DIRECTORY;

		var sv = new HttpServer(new Host("0.0.0.0"), 3000);

		sv.requestHandler.dynamicRouter.addDynamicRoute("/api/reload", new ApiReloadHandler());

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

			sv.requestHandler.dynamicRouter.addDynamicRoute(routename, new XHTMLRoute(fp));
			Logger.warn("New route: ", routename, " added.");
		};
		final handleDeletedFile = (fp:String) -> {
			if (!fp.endsWith(".xhtml") || !fp.endsWith(".md"))
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

		Thread.create("watcher", () -> {
			Logger.info("Watcher is now running!");
			watcher.run();
		});
		sv.start();
	}
}

class ApiReloadHandler extends AbstractHandler {
	public function GET(event:RequestEvent) {
		return json({
			version: Main.VERSION
		});
	}
}
