package routes.api.hi;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class ServerHandler extends AbstractHandler {
	public function new() {}

	@:keep public function GET(event:RequestEvent) {
		text("Hello, Moonlit Crimson Dragon! IT WORKS!! i can change this mid execution!");
	}
}
