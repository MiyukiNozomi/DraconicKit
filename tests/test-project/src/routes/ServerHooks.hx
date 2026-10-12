package routes;

import ryuu.handling.RequestHandler.RequestEvent;
import ryuu.handling.AbstractHooks;

class ServerHooks extends AbstractServerHooks {
	public function new() {}

	public override function handle(ev:RequestEvent, resolve) {
		if (ev.url.pathname == "/hooks-are-you-there") {
			trace(ev);
			return text("YAGOOO!! 
			kidding, you actually found the secret route defined in ServerHooks.hx!");
		}

		resolve(ev);
	}
}
