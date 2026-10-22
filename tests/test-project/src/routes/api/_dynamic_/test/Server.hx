package routes.api._dynamic_.test;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class Server extends AbstractHandler {
	@:keep public function GET(event:RequestEvent) {
		json({
			message: "HI from the placeholder one!",
			params: event.params
		});
	}
}
