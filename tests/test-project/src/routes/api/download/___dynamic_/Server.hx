package routes.api.download.___dynamic_;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class Server extends AbstractHandler {
	@:keep public function GET(event:RequestEvent) {
		json({
			message: "HI from the variadic one!",
			params: event.params
		});
	}
}
