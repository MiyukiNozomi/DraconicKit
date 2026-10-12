package routes.api.hi;

import haxe.Json;
import ryuu.handling.RequestHandler.RequestEvent;
import ryuu.handling.AbstractHandler;

class ServerHandler extends AbstractHandler {
	public function new() {}

	@:keep public function GET(event:RequestEvent) {
		text("Hello, Moonlit Crimson Dragon! your locals are " + Json.stringify(event.locals));
	}
}
