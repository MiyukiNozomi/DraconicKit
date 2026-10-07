package ryuu.handling;

import ryuu.handling.Routing.DynamicRouter;
import ryuu.handling.AbstractHandler;
import haxe.Constraints.Function;
import java.lang.Error;
import ryuu.std.MimeTypes;
import sys.io.File;
import ryuu.http.HttpMessages.HttpResponse;
import ryuu.std.URL;
import ryuu.Console.Logger;
import haxe.io.Path;
import haxe.io.Error;
import sys.FileSystem;
import ryuu.http.HttpMessages.HttpRequest;
import ryuu.http.HttpSocket;

typedef RequestEvent = {
	socket:HttpSocket,
	req:HttpRequest,
	params:Map<String, String>
}

/**

	Oh boy.. get ready for the huge list of TODOs;

	- Actual HMR:
	  |_ WebSockets
	  |_ Detecting file system changes
	  |_ Emit said changes and update the page locally
	- Custom Routes:
	  |_ Load Haxe files and search for them on a 'source/routes' folder
	  |_ Compile said haxe files
	  |_ Load request handlers from them
	  |_ Have HMR with them...
	- Svelte
	  |_ find a JS runtime that can run the svelte compiler
	  |_ have svelte components building in routes
	  |_ Server side rendering


	aaaaand there's a lot more crap i have to do

**/
final class RequestHandler {
	private var staticRoutes:Array<String>;

	private var staticRouteBasedir:String;

	public var dynamicRouter(default, null):DynamicRouter;

	public function new() {
		this.staticRouteBasedir = Path.join([Configuration.WorkingDirectory, Configuration.StaticDirectory]);
		this.staticRoutes = new Array();
		this.dynamicRouter = new DynamicRouter();
	}

	public function loadStaticRoutes() {
		if (!FileSystem.exists(staticRouteBasedir))
			throw Error.Custom(staticRouteBasedir + ": directory does not exist.");

		this.staticRoutes = new Array();

		var readDirRecursive:(String, String) -> Void;
		readDirRecursive = (basedir:String, pathname:String) -> {
			if (FileSystem.isDirectory(pathname)) {
				var entries = FileSystem.readDirectory(pathname);
				for (entry in entries)
					readDirRecursive(basedir, Path.join([basedir, entry]));
			} else {
				staticRoutes.push(pathname.substring(basedir.length));
			}
		};

		readDirRecursive(staticRouteBasedir, staticRouteBasedir);

		Logger.debug("Base directory: ", staticRouteBasedir);
		Logger.debug("Static routes:", "\n" + (this.staticRoutes.map(v -> ' - ${v}').join("\n")));
	}

	public function handleRequest(socket:HttpSocket, req:HttpRequest) {
		var url = new URL(req.status.target, "http://0.0.0.0");
		Logger.debug(req.status.method, url.href, req.status.version);

		if (staticRoutes.contains(url.pathname)) {
			if (req.status.method != "GET")
				throw new HttpResponse(405);

			var fileStream = File.read(Path.join([this.staticRouteBasedir, url.pathname]));
			throw new HttpResponse(200, ["content-type" => MimeTypes.forFilename(url.pathname)], fileStream);
		}

		this.dynamicRouter.tryHandleRequest(socket, url, req);
		throw new HttpResponse(404);
	}
}
