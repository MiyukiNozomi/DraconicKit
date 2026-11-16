package shinku.internal.devserver.routes;

import shinku.http.HttpMessages.HttpResponse;
import haxe.io.Path;
import sys.io.File;
import shinku.internal.js.esm.ESMResolver;
import shinku.Console.Logger;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

class ESModuleResolveRoute extends AbstractHandler {
	public function GET(event:RequestEvent<Dynamic>) {
		var modulePath = event.params.get("path");
		var scriptDir = event.url.searchParams.get("draconicKitScriptPath");

		if (modulePath == null)
			return text("modulePath is NULL (this is a bug by the way, report it to miyuki, not akane!)", {status: 400});
		if (scriptDir == null)
			return text("draconicKitScriptPath search parameter is missing!", {status: 400});

		try {
			redirect(302, Path.join([
				"/@draconickit/module",
				ESMResolver.esmResolve(modulePath, Path.join(['./', scriptDir]))
			]));
		} catch (res:HttpResponse) {
			throw res;
		} catch (err) {
			Logger.error("Could not resolve:", modulePath, "in script dir", scriptDir, "\n", err);
			text("Could not resolve: " + modulePath + " check logs for details.", {status: 400});
		}
	}
}
