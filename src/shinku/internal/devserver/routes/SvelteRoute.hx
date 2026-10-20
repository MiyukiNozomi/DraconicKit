package shinku.internal.devserver.routes;

import haxe.Json;
import haxe.io.Path;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.internal.interop.Svelte.SvelteBuilder;
import sys.io.File;

#if dev
class SvelteRoute extends AbstractHandler {
	private var thisPathname:String;

	public var serverPage:Null<AbstractServerPage>;

	private var eTag:String = "";
	private var cachedPageSrc:{
		js:String,
		css:String
	} = {js: "", css: ""};

	public function new(serverPage:Null<AbstractServerPage>, thisPathname:String) {
		this.serverPage = serverPage;
		this.thisPathname = thisPathname;
	}

	@:keep public function GET(event:RequestEvent) {
		final searchParams = event.url.searchParams;

		var component = SvelteBuilder.getComponent(this.thisPathname);

		if (searchParams.has("shinkureqtype")) {
			var script = SvelteBuilder.getComponentScript(component, event.url.pathname, searchParams);
			return text(script, {
				status: 200,
				headers: ["content-type" => "text/javascript"]
			});
		}

		var appPage = File.getContent(Path.join([Configuration.WorkingDirectory, "src/app.html"]));

		var head = "";
		var body = "";

		body += '<script type="module">${JavaScriptTransformer.transform('import { mount } from "svelte";
		import App from ${Json.stringify(event.url.pathname + "?shinkureqtype=script")};

mount(App, {
	target: document.querySelector("#app-container"),
	props: ${Json.stringify(serverPage != null ?serverPage.pageServerLoad(event) : {})}
});',  component.filename)}</script>';

		appPage = StringTools.replace(appPage, "%draconic.svelte.head%", head);
		appPage = StringTools.replace(appPage, "%draconic.svelte.body%", body);

		return text(appPage, {
			status: 200,
			headers: ["content-type" => "text/html"]
		});
	}
}
#end
