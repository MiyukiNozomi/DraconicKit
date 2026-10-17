package shinku.handling;

import shinku.handling.AbstractHooks.AbstractServerHooks;
import haxe.io.Error;
import shinku.Console.Logger;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.http.HttpMessages.HttpRequest;
import shinku.http.HttpMessages.HttpResponse;
import shinku.http.HttpSocket;
import shinku.std.URL;

typedef DynamicHandler = {
	instance:AbstractHandler,
	methodToCallbackMap:Map<String, Dynamic>
}

typedef RouteEntry = {
	rawRoutePath:String,
	segments:Array<RouteSegment>,
	isVariadic:Bool,
	handler:DynamicHandler,
}

typedef RouteSegment = {
	name:String,
	isDynamic:Bool
}

class DynamicRouter {
	public var routes:Array<RouteEntry>;

	private var hooks:Null<AbstractServerHooks>;

	public function new() {
		this.hooks = null;
		this.routes = new Array();
	}

	public function setServerHooks(hooks:Null<AbstractServerHooks>) {
		this.hooks = hooks;
	}

	public function removeAllRoutes() {
		this.routes = new Array();
	}

	public function removeRouteByName(name:String) {
		for (i => rt in this.routes) {
			if (rt.rawRoutePath == name) {
				this.routes.remove(rt);
				return true;
			}
		}
		return false;
	}

	public function getRouteByName(name:String):Null<RouteEntry> {
		for (i => rt in this.routes) {
			if (rt.rawRoutePath == name) {
				return rt;
			}
		}
		return null;
	}

	public function addDynamicRoute<T:AbstractHandler>(path:String, handler:T) {
		var entryInfo = this.parseRoute(path);

		var clazz = Type.getClass(handler);
		if (clazz == null)
			throw Error.Custom("Not a valid class.");
		var fields = Type.getInstanceFields(clazz);

		var handlerEntry:DynamicHandler = {
			instance: handler,
			methodToCallbackMap: new Map()
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

			handlerEntry.methodToCallbackMap.set(field, method);
		}

		if (handlerEntry.methodToCallbackMap.size() == 0) {
			throw Error.Custom("The handler: "
				+ path
				+ " has no handler callbacks. please remove it or introduce a function with like: @:keep public function GET(event : Request Event) {.");
		}

		this.routes.push({
			rawRoutePath: path,
			segments: entryInfo.entries,
			isVariadic: entryInfo.isRouteVariadic,
			handler: handlerEntry
		});

		var list = new Array();
		for (key => _ in handlerEntry.methodToCallbackMap) {
			list.push(key);
		}
		Logger.debug("Supported methods in dynamic route " + path + " are: " + list.join(', '));
	}

	public function tryHandleRequest(socket:HttpSocket, url:URL, req:HttpRequest) {
		var e:RequestEvent = {
			socket: socket,
			req: req,
			url: url,
			locals: {},
			params: []
		};

		final resolve = (event:RequestEvent) -> {
			for (dynamicRoute in this.routes) {
				var params = this.matchRoute(dynamicRoute, url.pathname);

				if (params != null) {
					var handler = dynamicRoute.handler.methodToCallbackMap.get(req.status.method);

					if (handler != null) {
						event.params = params;
						Reflect.callMethod(dynamicRoute.handler.instance, handler, [event]);
					} else {
						throw new HttpResponse(405);
					}
					break;
				}
			}
		}

		if (this.hooks != null) {
			this.hooks.handle(e, resolve);
		} else {
			resolve(e);
		}
	}

	private function matchRoute(route:RouteEntry, pathname:String):Null<Map<String, String>> {
		var components = pathname.split('/').filter(v -> v.length > 0);

		if (!route.isVariadic && components.length != route.segments.length)
			return null;

		if (route.isVariadic && components.length < route.segments.length - 1)
			return null;

		var params = new Map<String, String>();

		for (i in 0...route.segments.length) {
			var segment = route.segments[i];

			if (segment.isDynamic) {
				if (route.isVariadic && i == route.segments.length - 1) {
					params.set(segment.name, components.slice(i).join('/'));
					break;
				}

				params.set(segment.name, components[i]);
			} else {
				if (components[i] != segment.name)
					return null;
			}
		}

		return params;
	}

	private function parseRoute(pathname:String) {
		var components = pathname.split('/').filter(v -> v.length > 0);
		var entries = new Array<RouteSegment>();
		var isRouteVariadic = false;

		var comp;
		while ((comp = components.shift()) != null) {
			if (StringTools.startsWith(comp, "[") && StringTools.endsWith(comp, "]")) {
				var cleanName = comp.substring(1, comp.length - 1);
				var isLast = components.length == 0;

				if (StringTools.startsWith(cleanName, "...")) {
					if (isLast) {
						isRouteVariadic = true;
						cleanName = cleanName.substring(3);
					} else {
						throw Error.Custom("Invalid route: " + pathname + ", because a variadic parameter can only be at the end of the route's path.");
					}
				}

				if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(cleanName))
					throw Error.Custom("Invalid route: " + pathname + ", because clean name is not complaint with HAXE's identifier rules.");
				entries.push({
					name: cleanName,
					isDynamic: true
				});
			} else {
				entries.push({
					name: comp,
					isDynamic: false
				});
			}
		}

		return {
			isRouteVariadic: isRouteVariadic,
			entries: entries
		};
	}
}
