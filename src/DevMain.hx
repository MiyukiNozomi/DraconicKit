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

	private static function compileHaxe() {
		final shinkuDir = Path.join([Configuration.WorkingDirectory, ".shinku"]);
		FileSystem.createDirectory(shinkuDir);

		final hacksDir = Path.join([shinkuDir, "hacks"]);
		FileSystem.createDirectory(hacksDir);

		final hxmlFilePath = Path.join([shinkuDir, "build.hxml"]);
		if (!FileSystem.exists(hxmlFilePath)) {
			File.saveContent(hxmlFilePath, '
# just sanity check
-dce std
--class-path src
--class-path .shinku/hacks
--class-path ${FileSystem.absolutePath(Path.join([SystemTools.thisHomeDir(), "src/"]))}
--main StubsMain
--jvm .shinku/DynamicServerCode.jar
');
		}

		var haxeFiles = new Array<String>();
		SystemTools.visitDirRecursive(srcDir, (fp) -> {
			if (fp.endsWith(".hx"))
				haxeFiles.push(fp);
		});

		final stubMainPath = Path.join([hacksDir, "StubsMain.hx"]);
		if (!FileSystem.exists(stubMainPath)) {
			final stubsMainCode = '
@:build(IncludeAll.run("../../src"))
class StubsMain {
	static function main() {
		trace("DO NOT RUN THIS! - this is not your server! read the docs!"); 
	}
}		
';
			File.saveContent(stubMainPath, stubsMainCode);
		}
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

		final handleNewFile = (fp:String) -> {
			var route = getRoutename(fp);
			if (route != null) {
				if (fp.endsWith(".svelte")) {
					Logger.debug("Adding route: ", route, " (svelte)");
					httpServer.requestHandler.dynamicRouter.addDynamicRoute(route, new SvelteRoute(null, fp.substring(Path.directory(srcDir).length + 1)));
				} else if (fp.endsWith(".hx")) {
					Logger.debug("Haxe file changed: ", fp, " for route: ", route);
					compileHaxe();
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
