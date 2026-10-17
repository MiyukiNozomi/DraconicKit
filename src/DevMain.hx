import shinku.handling.AbstractHandler;
import shinku.internal.backend.HotReloader.HotReloader;
import shinku.internal.backend.HaxeBuilder;
import haxe.io.Path;
import shinku.Configuration;
import shinku.Console.Logger;
import shinku.http.HttpServer;
import shinku.internal.ESModuleRoute;
import shinku.internal.NodeRunner;
import shinku.internal.SvelteRoute;
import shinku.std.io.FileWatcher;
import shinku.std.io.SystemTools;
import sys.FileSystem;
import sys.io.File;
import sys.net.Host;
import sys.thread.Thread;

using Lambda;
using StringTools;

class DevMain {
	private static var srcDir:String;
	private static var builder:HaxeBuilder;

	private static function getRoutename(fp:String) {
		final normalizedPath = fp.substring(srcDir.length);
		if (!normalizedPath.startsWith("/routes")
			|| (!normalizedPath.endsWith("Server.hx") && !normalizedPath.endsWith(".svelte") && !normalizedPath.endsWith("ServerPage.hx")))
			return null;

		var routeName = Path.directory(normalizedPath.substring("/routes".length));
		if (routeName.length == 0)
			routeName = "/";
		return routeName;
	}

	static function main() {
		Sys.println("Hello there!
        
You've launched the development version of DraconicKit. if you  intended this, it's fine! But if this is supposed to be a production environment,
you're in big trouble!");
		Configuration.WorkingDirectory = "tests/test-project";

		NodeRunner.ensureNodeJSIsInstalled();

		// TODO: read config
		final httpServer = new HttpServer(new Host("localhost"), 8173);
		httpServer.requestHandler.dynamicRouter.addDynamicRoute("/@module/[...path]", new ESModuleRoute());

		final httpServerThread = Thread.create("HttpServerThread", () -> {
			httpServer.start();
		});

		srcDir = FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, "src"]));
		final hotReloader = new HotReloader((cls, name) -> {
			if (!name.startsWith("routes."))
				return [];

			try {
				var clsInstance = cls.newInstance();

				var handlerInstance = Std.downcast(clsInstance, AbstractHandler);
				var serverPageInstance = Std.downcast(clsInstance, AbstractServerPage);

				// route-like instancess
				var routename = '/' + Path.directory(name.substring("routes.".length).split('.').join('/'));
				trace(routename);
				if (handlerInstance != null) {
					httpServer.requestHandler.dynamicRouter.addDynamicRoute(routename, handlerInstance);
					return [routename];
				} else if (serverPageInstance != null) {
					// we need to find an existing svelte route, or re-create it.
					var existing = httpServer.requestHandler.dynamicRouter.getRouteByName(routename);
					if (existing != null) {
						var sveltePage = Std.downcast(existing.handler.instance, SvelteRoute);

						if (sveltePage != null) {
							sveltePage.serverPage = serverPageInstance;
							return ["server-page:" + routename];
						}
					}
					Logger.warn("WARNING: You have a ServerPage.hx on " + routename + " that has no matching +page.svelte, this will have no effect.");
				} else {
					Logger.debug("This class: ", cls,
						" does not extend either AbstractHandler, or AbstractServerPage, we can't be sure of what it was because we cant tell what it's original filename was." +
						"so we will politely ignore it.");
				}
				return [];
			} catch (e) {
				Logger.error("Could not instantiate " + cls.toString() + " because: ", e.message);
				Logger.debug("Full exception of why: ", e);
				return [];
			}
		}, (route) -> {
			if (route.startsWith("server-page:")) {
				var trueRoutename = route.substring("server-page:".length);
				trace(trueRoutename);
				var existing = httpServer.requestHandler.dynamicRouter.getRouteByName(trueRoutename);
				if (existing != null) {
					var sveltePage = Std.downcast(existing.handler.instance, SvelteRoute);
					sveltePage.serverPage = null;
				}
			} else {
				httpServer.requestHandler.dynamicRouter.removeRouteByName(route);
			}
		});

		builder = new HaxeBuilder(FileSystem.absolutePath(Configuration.WorkingDirectory), jar -> hotReloader.reload(jar),
			errors -> Logger.debug("Haxe build failed:
", errors));

		final handleNewFile = (fp:String) -> {
			var route = getRoutename(fp);
			if (route != null) {
				if (fp.endsWith(".svelte")) {
					Logger.debug("Adding route: ", route, " (svelte)");
					httpServer.requestHandler.dynamicRouter.addDynamicRoute(route, new SvelteRoute(null, fp.substring(Path.directory(srcDir).length + 1)));
				} else if (fp.endsWith(".hx")) {
					Logger.debug("Haxe file changed: ", fp, " for route: ", route);
					builder.request();
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
