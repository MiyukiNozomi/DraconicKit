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
		var modulePath = event.url.searchParams.get("modulePath");
		var scriptDir = event.url.searchParams.get("draconicKitScriptPath");

		if (modulePath == null)
			return text("modulePath search parameter is missing!", {status: 400});
		if (scriptDir == null)
			return text("draconicKitScriptPath search parameter is missing!", {status: 400});

		try {
			redirect(302, JavaScriptTransformer.resolveImport(modulePath, scriptDir));
		} catch (res:HttpResponse) {
			throw res;
		} catch (err) {
			Logger.error("Could not resolve:", modulePath, "in script dir", scriptDir, "\n", err);
			text("Could not resolve: " + modulePath + " check logs for details.", {status: 400});
		}
	}
}
