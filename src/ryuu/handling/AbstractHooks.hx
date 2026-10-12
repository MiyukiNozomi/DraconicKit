package ryuu.handling;

import ryuu.handling.RequestHandler.RequestEvent;

abstract class AbstractServerHooks extends HandlerTools {
	public function onServerInit() {}

	public function handle(event:RequestEvent, resolve:(event:RequestEvent) -> Void) {
		resolve(event);
	}
}
