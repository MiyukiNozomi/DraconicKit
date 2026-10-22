package shinku.internal.devserver;

import shinku.Console.AnsiPrinter;
#if draconicbuilder
import haxe.io.Path;
import shinku.Configuration;
import shinku.Console.Logger;
import shinku.handling.AbstractHandler;
import shinku.http.HttpServer;
import shinku.internal.DraconicConfig.DraconicJSConfigLoader;
import shinku.internal.devserver.routes.ESModuleRoute;
import shinku.internal.esm.NodeRunner;
import shinku.std.io.FileWatcher;
import shinku.std.io.SystemTools;
import sys.net.Host;
import sys.thread.Mutex;
import sys.thread.Thread;

using Lambda;
using StringTools;

class DevServer {
	public static var builderThread:Null<Thread>;

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

		final httpServer = new HttpServer(new Host(serverConfig.server.host), serverConfig.server.port);

		httpServer.requestHandler.dynamicRouter.addDynamicRoute("/@module/[...path]", new ESModuleRoute());

		httpServer.onListen = () -> {
			printWelcome(httpServer);

			builderThread = Thread.create("DraconicBuilder", () -> {
				DraconicBuilder.runBuilderProcess(httpServer);
			});
		}

		httpServer.start();
	}
}
#end
