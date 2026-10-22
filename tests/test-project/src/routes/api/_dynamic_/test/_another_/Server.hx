package routes.api._dynamic_.test._another_;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class Server extends AbstractHandler {
	@:keep public function GET(event:RequestEvent) {
		json({
			message: "HI from the two placeholder one!",
			params: event.params
		});
	}
}
