package ryuu.handling;

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
}

private typedef DynamicHandler = {
	instance:AbstractHandler,
	handlers:Map<String, Dynamic>
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
	private var dynamicRoutes:Map<String, DynamicHandler>;
	private var staticRouteBasedir:String;

	public function new() {
		this.staticRouteBasedir = Path.join([Configuration.WorkingDirectory, Configuration.StaticDirectory]);
		this.staticRoutes = new Array();
		this.dynamicRoutes = new Map<String, DynamicHandler>();
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

	public function addDynamicRoute<T:AbstractHandler>(path:String, handler:T) {
		var clazz = Type.getClass(handler);
		if (clazz == null)
			throw Error.Custom("Not a valid class.");
		var fields = Type.getInstanceFields(clazz);

		var entry:DynamicHandler = {
			instance: handler,
			handlers: new Map()
		};

		for (field in fields) {
			var method = Reflect.field(handler, field);
			if (method == null || !Reflect.isFunction(method))
				continue;

			if (!HttpSocket.ACCEPTED_METHODS.contains(field)) {
				if (~/\b[A-Z]+\b/.match(field)) {
					Sys.println("\nWARNING: In handler for "
						+ path
						+ " there is a method named: "
						+ field
						+ ". but this is not a valid http header. please only put functions with fully upper-case names for HTTP request handling.\n");
				}
				continue;
			}

			entry.handlers.set(field, method);
		}

		if (entry.handlers.size() == 0) {
			throw Error.Custom("The handler: "
				+ path
				+ " has no handler callbacks. please remove it or introduce a function with like: @:keep public function GET(event : Request Event) {.");
		}
		this.dynamicRoutes.set(path, entry);

		var list = new Array();
		for (key => _ in entry.handlers) {
			list.push(key);
		}
		Logger.debug("Supported methods in dynamic route " + path + " are: " + list.join(', '));
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

		var dynamicRoute = this.dynamicRoutes.get(url.pathname);

		if (dynamicRoute != null) {
			var handler = dynamicRoute.handlers.get(req.status.method);

			if (handler != null) {
				var event:RequestEvent = {
					socket: socket,
					req: req
				};
				Reflect.callMethod(dynamicRoute.instance, handler, [event]);
			} else {
				throw new HttpResponse(405);
			}
		}

		throw new HttpResponse(404);
	}
}
