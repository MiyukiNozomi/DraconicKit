package shinku.internal.devserver.routes;

import haxe.atomic.AtomicInt;
import haxe.atomic.AtomicBool;
#if draconicbuilder
import shinku.Console.Logger;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.tools.ServerSentEvents.ServerEventsAction;
import hx.concurrent.collection.SynchronizedMap;

class HMRChannelRoute extends AbstractHandler {
	public function new() {
		super();
	}

	private var needToReload = new AtomicBool(false);

	public function requestInvalidateAll() {
		needToReload.store(true);
	}

	public function GET(event:RequestEvent) {
		ServerEventsAction.upgrade(event, (writer) -> {
			// writer.id(1);
			// writer.event("banana", "i got nothin!");

			// just let it sleep indefinitely now
			var lastUpdate = Sys.time();
			while (true) {
				Sys.sleep(0.1);

				if (needToReload.compareExchange(true, false)) {
					writer.event("invalidate-all", "A full reload has been requested.");
					lastUpdate += 5;
				}

				if (Sys.time() - lastUpdate > 5) {
					writer.comment("ping!");
					lastUpdate += 5;
				}
			}
		}, () -> {
			Logger.debug("Client has disconnected!");
		});
	}
}
#end
