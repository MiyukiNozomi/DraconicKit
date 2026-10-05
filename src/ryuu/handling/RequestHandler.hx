package ryuu.handling;

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

class RequestHandler {
	private var staticRoutes:Array<String>;
	private var staticRouteBasedir:String;

	public function new() {
		this.staticRouteBasedir = "/dev/null";
		this.staticRoutes = new Array();
	}

	public function loadStaticRoutes(basedir:Null<String> = null) {
		if (basedir == null)
			basedir = FileSystem.absolutePath("static");

		if (!FileSystem.exists(basedir))
			throw Error.Custom("static/ directory does not exist.");

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

		this.staticRouteBasedir = basedir;
		readDirRecursive(basedir, basedir);

		Logger.debug("Base directory: ", basedir);
		Logger.debug("Static routes:", "\n" + (this.staticRoutes.map(v -> ' - ${v}').join("\n")));
	}

	public function handleRequest(socket:HttpSocket, req:HttpRequest) {
		var url = new URL(req.status.target, "http://0.0.0.0");
		Logger.debug(req.status.method, url.href, req.status.version);

		if (staticRoutes.contains(url.pathname)) {
			var fileStream = File.read(Path.join([this.staticRouteBasedir, url.pathname]));
			throw new HttpResponse(200, {
				"content-type": MimeTypes.forFilename(url.pathname)
			}, fileStream);
		}

		throw new HttpResponse(404);
	}
}
