package ryuu.internal;

import haxe.io.Bytes;
import ryuu.http.HttpMessages.HttpResponse;
import sys.FileSystem;
import haxe.io.Path;
import sys.io.File;
import ryuu.handling.RequestHandler.RequestEvent;
import ryuu.handling.AbstractHandler;

class SvelteRouter extends AbstractHandler {
	private var thisPathname:String;

	private var serverPage:Null<AbstractServerPage>;

	public function new(serverPage:AbstractServerPage, thisPathname:String) {
		this.serverPage = serverPage;
		this.thisPathname = thisPathname;
	}

	@:keep public function GET(event:RequestEvent) {
		// TODO: make production builds load these into memory and not every time.

		if (!FileSystem.exists(this.thisPathname)) {
			error(404, "File not found on disk: " + this.thisPathname);
		}

		if (event.url.search.indexOf("script") != -1) {
			throw new HttpResponse(200, ["content-type" => "text/javascript; charset=utf-8"],
				Bytes.ofString(JavaScriptTransformer.transform(File.read(Path.join([this.thisPathname, "page.js"])).readAll().toString())));
		}

		var appPage = Configuration.SvelteBaseHTML + "";

		var head = '

';
		var body = "";

		var cssPath = Path.join([this.thisPathname, "page.css"]);
		if (FileSystem.exists(cssPath)) {
			head += '<style>${File.read(cssPath).readAll().toString()}</style>';
		}
		// TODO: make server page do something

		//	head += '<script type="module" src="${event.url.pathname}?script=true"></script>';

		body += '<script type="module">
		import { mount } from "/@module/svelte";
		import App from "./?script=true";

mount(App, {
	target: document.querySelector("#app-container"),
	props: {}
});
</script>';

		appPage = StringTools.replace(appPage, "%draconic.svelte.head%", head);
		appPage = StringTools.replace(appPage, "%draconic.svelte.body%", body);

		throw new HttpResponse(200, ["content-type" => "text/html"], Bytes.ofString(appPage));
	}
}
