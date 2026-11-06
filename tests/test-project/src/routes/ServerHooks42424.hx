package routes;

import shinku.http.HttpMessages.HttpResponse;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHooks.AbstractServerHooks;

class ServerHooks extends AbstractServerHooks {
	public override function handle(event:RequestEvent<Dynamic>, resolve:(event:RequestEvent<Dynamic>) -> Void) {
		try {
			resolve(event);
		} catch (e:HttpResponse) {
			trace("hey?");
			text("Excuse me? I am a teapot! I will not reply (but will execute)", {
				status: 418,
				headers: []
			});
		}
	}
}
