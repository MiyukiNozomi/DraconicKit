package routes.api.hi;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

@:customRoute("banana")
class ServerHandler extends AbstractHandler {
	@:keep public function GET(event:RequestEvent) {
		text("Hello, Moonlit Crimson Dragon! yay");
	}
}
