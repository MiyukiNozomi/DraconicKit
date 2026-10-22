package shinku.internal.devserver;

import shinku.Console.AnsiPrinter;
import shinku.std.io.FileWatcher;
import shinku.std.io.SystemTools;
import shinku.internal.jvm.HaxeExtractor;
import shinku.internal.jvm.HaxeBuilder;
import shinku.handling.AbstractHandler;
import shinku.handling.AbstractHooks.AbstractServerHooks;
import shinku.internal.jvm.HotReloader;
import shinku.Console.Logger;
import sys.FileSystem;
import shinku.internal.devserver.routes.SvelteRoute;
import haxe.io.Path;
import sys.thread.Mutex;
import shinku.handling.AbstractHandler.AbstractServerPage;
import shinku.http.HttpServer;

using StringTools;

class DraconicBuilder {
	private static var srcDir:String = "/dev/null";

	private static final serverPages = new Map<String, AbstractServerPage>();
	// build thread and watcher thread both touch this
	private static final pagesLock = new Mutex();

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

	private static function attachServerPage(httpServer:HttpServer, routename:String) {
		pagesLock.acquire();
		final page = serverPages.get(routename); // null = detach
		pagesLock.release();
		final existing = httpServer.requestHandler.dynamicRouter.getRouteByName(routename);
		if (existing == null)
			return false;
		final svelte = Std.downcast(existing.handler.instance, SvelteRoute);
		if (svelte == null)
			return false;
		svelte.serverPage = page;
		return true;
	}

	public static function runBuilderProcess(httpServer:HttpServer) {
		srcDir = FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, "src"]));
		Logger.debug("src directory is: ", srcDir);

		final hotReloader = new HotReloader((cls, name) -> {
			if (!name.startsWith("routes."))
				return [];

			try {
				var clsInstance = cls.newInstance();

				trace("For ", cls, " i have ", cls.getSuperclass().getMethods().toArray().map(v -> v.getName()));

				var handlerInstance = Std.downcast(clsInstance, AbstractHandler);
				var serverPageInstance = Std.downcast(clsInstance, AbstractServerPage);
				var serverHooksIntance = Std.downcast(clsInstance, AbstractServerHooks);

				if (cls.getPackage().getName() == "routes" && serverHooksIntance != null) {
					httpServer.requestHandler.dynamicRouter.setServerHooks(serverHooksIntance);
					try {
						serverHooksIntance.onServerInit();
					} catch (e) {
						Logger.error(e);
					}
					return ["server:hooks"];
				}

				// route-like instancess
				var routename = '/' + Path.directory(name.substring("routes.".length).split('.').join('/'));
				if (handlerInstance != null) {
					httpServer.requestHandler.dynamicRouter.addDynamicRoute(routename, handlerInstance);
					return [routename];
				} else if (serverPageInstance != null) {
					pagesLock.acquire();
					serverPages.set(routename, serverPageInstance);
					pagesLock.release();

					// we need to find an existing svelte route, or re-create it.
					if (!attachServerPage(httpServer, routename))
						Logger.warn("WARNING: You have a ServerPage.hx on " + routename + " that has no matching +page.svelte, this will have no effect.");
					return ["server-page:" + routename];
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
			if (route == "server:hooks") {
				httpServer.requestHandler.dynamicRouter.setServerHooks(null);
			} else if (route.startsWith("server-page:")) {
				final trueRoutename = route.substring("server-page:".length);
				pagesLock.acquire();
				serverPages.remove(trueRoutename);
				pagesLock.release();
				attachServerPage(httpServer, trueRoutename); // registry is empty now, so this detaches
			} else {
				httpServer.requestHandler.dynamicRouter.removeRouteByName(route);
			}
		});

		var builder = new HaxeBuilder(FileSystem.absolutePath(Configuration.WorkingDirectory), jar -> hotReloader.reload(jar),
			errors -> Logger.error("Haxe build failed:
", errors));

		final handleNewFile = (fp:String) -> {
			var route = getRoutename(fp);

			if (fp.endsWith(".hx")) {
				Logger.debug("Haxe file changed: ", fp, " for route: (if route is null, this is 100% a library or server hooks).", route);
				builder.request();
				return;
			}

			if (route != null) {
				if (fp.endsWith(".svelte")) {
					Logger.debug("Adding route: ", route, " (svelte)");
					final svelte = new SvelteRoute(null, fp.substring(Path.directory(srcDir).length + 1));
					pagesLock.acquire();
					svelte.serverPage = serverPages.get(route); // set before the route goes live
					pagesLock.release();
					httpServer.requestHandler.dynamicRouter.addDynamicRoute(route, svelte);
				} else {
					Logger.debug("Route not implemented: ", route, " at ", fp);
				}
			}
		}

		final handleFileDeletion = (fp:String) -> {
			var route = getRoutename(fp);
			if (route != null
				&& (!fp.endsWith(".hx")
					|| (HaxeExtractor.getClassInformation(fp, "AbstractServerPage").extendedClass != "AbstractServerPage"))) {
				Logger.debug("Deleted route for ", fp, " ?", httpServer.requestHandler.dynamicRouter.removeRouteByName(route));
			}
		}

		// lets build our structure first, then we initiate the watcher.
		SystemTools.visitDirRecursive(srcDir, handleNewFile);

		var watcher = new FileWatcher(srcDir, e -> switch e {
			case Added(p): {
					AnsiPrinter.print('§1;32m+ §0;90m$p\n');
					handleNewFile(FileSystem.absolutePath(p));
				}
			case Modified(p): {
					AnsiPrinter.print('§1;33m~ §0;90m$p\n');
					final fullPath = FileSystem.absolutePath(p);
					if (!fullPath.endsWith(".svelte"))
						handleFileDeletion(fullPath);
					handleNewFile(fullPath);
				}
			case Removed(p): {
					AnsiPrinter.print('§1;31m- §0;90m$p\n');
					handleFileDeletion(FileSystem.absolutePath(p));
				}
		}, 300, p -> p.indexOf("node_modules") != -1 || p.indexOf(".git") != -1);
		watcher.run();
	}
}
