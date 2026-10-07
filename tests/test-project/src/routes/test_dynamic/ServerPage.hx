package routes.test_dynamic;

import ryuu.handling.RequestHandler.RequestEvent;
import ryuu.handling.AbstractHandler.AbstractServerPage;

class ServerPage extends AbstractServerPage {
	public function pageServerLoad(event:RequestEvent) {
		return {
			message: "hello?"
		};
	};
}
