package routes;

import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHooks.AbstractServerHooks;

class ServerHooks extends AbstractServerHooks {
	public override function onServerInit() {
		trace("Hey! i do actually work too!");
	}

	public override function handle(event:RequestEvent<Dynamic>, resolve:(event:RequestEvent) -> Void) {
		trace("Attempt four? six twelve :", event);
		resolve(event);
	}
}
