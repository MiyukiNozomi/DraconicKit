package shinku.internal.devserver.routes;

#if draconicbuilder
import shinku.Console.Logger;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.tools.ServerSentEvents.ServerEventsAction;

class HMRChannelRoute extends AbstractHandler {
	public function GET(event:RequestEvent) {
		ServerEventsAction.upgrade(event, (writer) -> {
			writer.id(1);
			writer.event("banana", "i got nothin!");

			// just let it sleep indefinitely now
			while (true) {
				writer.comment("ping!");
				Sys.sleep(5);
			}
		}, () -> {
			Logger.debug("Client has disconnected!");
		});
	}
}
#end
