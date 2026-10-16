import shinku.Console.Logger;
import shinku.internal.ESModuleRoute;
import shinku.internal.SvelteRoute;
import sys.thread.Thread;
import sys.FileSystem;
import shinku.std.io.SystemTools;
import sys.net.Host;
import shinku.http.HttpServer;
import shinku.internal.NodeRunner;
import haxe.io.Path;
import shinku.Configuration;
import shinku.std.io.FileWatcher;

using StringTools;

class DevMain {
	static function main() {
		Sys.println("Hello there!
        
You've launched the development version of DraconicKit. if you  intended this, it's fine! But if this is supposed to be a production environment,
you're in big trouble!");
		Configuration.WorkingDirectory = "tests/test-project";

		NodeRunner.ensureNodeJSIsInstalled();

		Logger.info("Test");
		Logger.warn("Test");
		Logger.error("Test");
		Logger.debug("Test");

		// TODO: read config
		final httpServer = new HttpServer(new Host("localhost"), 8173);
		httpServer.requestHandler.dynamicRouter.addDynamicRoute("/@module/[...path]", new ESModuleRoute());

		final httpServerThread = Thread.create("HttpServerThread", () -> {
			httpServer.start();
		});

		final srcDir = FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, "src"]));

		final getRoutename = (fp:String) -> {
			final normalizedPath = fp.substring(srcDir.length);
			if (!normalizedPath.startsWith("/routes")
				|| (!normalizedPath.endsWith("Server.hx")
					&& !normalizedPath.endsWith(".svelte")
					&& !normalizedPath.endsWith("ServerPage.hx")))
				return null;

			var routeName = Path.directory(normalizedPath.substring("/routes".length));
			if (routeName.length == 0)
				routeName = "/";
			return routeName;
		}

		final handleNewFile = (fp:String) -> {
			var route = getRoutename(fp);
			if (route != null) {
				if (fp.endsWith(".svelte")) {
					Logger.debug("Adding route: ", route, " (svelte)");
					httpServer.requestHandler.dynamicRouter.addDynamicRoute(route, new SvelteRoute(null, fp.substring(Path.directory(srcDir).length + 1)));
				} else {
					Logger.debug("Route not implemented: ", route, " at ", fp);
				}
			}
		}

		final handleFileDeletion = (fp:String) -> {
			var route = getRoutename(fp);
			if (route != null) {
				Logger.debug("Deleted route for ", fp, " ?", httpServer.requestHandler.dynamicRouter.removeRouteByName(route));
			}
		}

		// lets build our structure first, then we initiate the watcher.
		SystemTools.visitDirRecursive(srcDir, handleNewFile);

		var watcher = new FileWatcher(srcDir, e -> switch e {
			case Added(p): {
					Sys.println('+ $p');
					handleNewFile(FileSystem.absolutePath(p));
				}
			case Modified(p): {
					Sys.println('~ $p');
					var fullPath = FileSystem.absolutePath(p);
					handleFileDeletion(fullPath);
					handleNewFile(fullPath);
				}
			case Removed(p): {
					Sys.println('- $p');
					handleFileDeletion(FileSystem.absolutePath(p));
				}
		}, 300, p -> p.indexOf("node_modules") != -1 || p.indexOf(".git") != -1);
		watcher.run();
	}
}
