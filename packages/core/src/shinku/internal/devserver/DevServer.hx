package shinku.internal.devserver;

#if draconicbuilder
import esper.execution.NodeRunner;
import haxe.io.Path;
import shinku.Configuration;
import shinku.Console.AnsiPrinter;
import shinku.Console.Logger;
import shinku.http.HttpServer;
import shinku.internal.DraconicConfig.DraconicJSConfigLoader;
import shinku.internal.devserver.routes.ESModuleResolveRoute;
import shinku.internal.devserver.routes.ESModuleRoute;
import shinku.internal.js.ShinkuESMDep;
import shinku.std.io.FileWatcher;
import shinku.std.io.SystemTools;
import sys.FileSystem;
import sys.net.Host;
import sys.thread.Thread;

using Lambda;
using StringTools;

class DevServer {
	public static var builderThread:Null<Thread>;
	public static var staticDirWatcherThread:Null<Thread>;

	private static function printWelcome(httpServer:HttpServer) {
		final separator = '\u2501\u2501\u2501\u2501\u2501\u2501---------';
		final flipped = separator.split('');
		flipped.reverse();
		final flippedSeparator = flipped.join('');

		final host = httpServer.host;
		AnsiPrinter.print('
	
	§1;91mDRACONIC §0;95m\u2726§1;91m KIT §0;91m ${Configuration.Version}
		
	§1;33m\u276F§1;93m$separator§1;33m \u2726 §1;93m$flippedSeparator§1;33m\u276E

	§0;90mServer running at §0;91m http://${host.host}:${host.port}


	§1;33m\u276F§1;93m$separator§1;33m \u2726 §1;93m$flippedSeparator§1;33m\u276E

');
	}

	public static function runDevServer() {
		NodeRunner.ensureNodeJSIsInstalled();

		final serverConfig = DraconicJSConfigLoader.getConfig();
		if (serverConfig == null) {
			Sys.exit(-4);
			return;
		}
		DraconicJSConfigLoader.installConfig(serverConfig);

		if (Configuration.CleanupAlways) {
			final pth = Path.join([Configuration.WorkingDirectory, ".shinku"]);
			Logger.warn('CleanupAlways was set to true, $pth will be deleted!');
			SystemTools.deleteRecursive(pth);
		}

		ShinkuESMDep.setupModule(null, Configuration.CleanupAlways);

		final httpServer = new HttpServer(new Host(serverConfig.server.host), serverConfig.server.port);

		httpServer.requestHandler.dynamicRouter.addDynamicRoute("/@draconickit/module/[...path]", new ESModuleRoute());
		httpServer.requestHandler.dynamicRouter.addDynamicRoute("/@draconickit/resolve-dynamic", new ESModuleResolveRoute());

		httpServer.onListen = () -> {
			printWelcome(httpServer);

			builderThread = Thread.create("DraconicBuilder", () -> {
				DraconicBuilder.runBuilderProcess(httpServer);
			});

			staticDirWatcherThread = Thread.create("StaticFileWatcher", () -> {
				final staticDir = FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, Configuration.StaticDirectory]));
				final watcher = new FileWatcher(staticDir, (event) -> {
					Logger.debug("Static directory at", staticDir, "has changed! reloading static route...");
					httpServer.requestHandler.loadStaticRoutes();
				});
				watcher.run();
			});
		}

		httpServer.start();
	}
}
#end
