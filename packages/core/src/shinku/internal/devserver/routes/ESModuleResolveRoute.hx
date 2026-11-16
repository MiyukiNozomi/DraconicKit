package shinku.internal.devserver.routes;

#if draconicbuilder
import esper.transformation.JavaScriptTransformer;
import shinku.Console.Logger;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.http.HttpMessages.HttpResponse;

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
#end
