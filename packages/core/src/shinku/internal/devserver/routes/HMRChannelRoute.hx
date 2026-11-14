package shinku.internal.devserver.routes;

import shinku.ws.WebSocketController.WebSocketAction;
#if draconicbuilder
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class HMRChannelRoute extends AbstractHandler {
	public function GET(event:RequestEvent) {
		WebSocketAction.upgrade(event, "DraconicKit-HMR", (ws) -> {});
	}
}
#end
