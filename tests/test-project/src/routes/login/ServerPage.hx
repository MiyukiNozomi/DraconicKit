package routes.login;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler.AbstractServerPage;

class ServerPage extends AbstractServerPage {
	public function pageServerLoad(event:RequestEvent) {
		return {
			message: "hello from haxe! let's see. aaa. or did i"
		};
	}
}
