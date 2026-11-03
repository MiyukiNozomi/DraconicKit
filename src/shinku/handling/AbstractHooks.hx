package shinku.handling;

import shinku.handling.RequestHandler.RequestEvent;

/**
	A foundation for custom server hooks.
	Must be at the package routes;

	Please be aware that in a similar fashion to AbstractHandler, your class instance is re-used cross threads.
	Please synchronize or localize any mutable data inside of your hooks.
**/
abstract class AbstractServerHooks extends HandlerTools {
	public function new() {}

	public function onServerInit() {}

	public function handle(event:RequestEvent, resolve:(event:RequestEvent) -> Void) {
		resolve(event);
	}
}
