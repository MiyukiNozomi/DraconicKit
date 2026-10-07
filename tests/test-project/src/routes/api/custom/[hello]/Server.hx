package routes.api.custom.hello;

import ryuu.handling.RequestHandler.RequestEvent;
import ryuu.handling.AbstractHandler;

class ServerHandler extends AbstractHandler {
	public function new() {}

	@:keep public function GET(event:RequestEvent) {
		text("Hello! your parameters are: " + event.params.toString());
	}
}
