package shinku.handling;

import haxe.io.Error;
import haxe.io.Path;
import shinku.Console.Logger;
import shinku.handling.DynamicRouter;
import shinku.http.HttpMessages.HttpRequest;
import shinku.http.HttpMessages.HttpResponse;
import shinku.http.HttpSocket;
import shinku.std.MimeTypes;
import shinku.std.URL;
import sys.FileSystem;
import sys.io.File;

typedef RequestEvent<T = Dynamic> = {
	url:URL,
	socket:HttpSocket,
	req:HttpRequest,
	locals:T,
	params:Map<String, String>
}

final class RequestHandler {
	private var staticRoutes:Array<String>;

	private var staticRouteBasedir:String;

	public var dynamicRouter(default, null):DynamicRouter;

	public function new() {
		this.staticRouteBasedir = Path.join([Configuration.WorkingDirectory, Configuration.StaticDirectory]);
		trace("Working static directory: " + this.staticRouteBasedir);

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
				for (entry in entries) {
					if (entry.charAt(0) == '@')
						continue;
					readDirRecursive(basedir, Path.join([pathname, entry]));
				}
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
