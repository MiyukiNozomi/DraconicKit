package shinku.internal;

import haxe.DynamicAccess;
import haxe.crypto.Sha1;
import haxe.Json;
import haxe.io.Bytes;
import shinku.http.HttpMessages.HttpResponse;
import sys.FileSystem;
import haxe.io.Path;
import sys.io.File;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;

typedef SvelteCompileResult = {
	/** The compiled JavaScript */
	js:{
		/** The generated code */
		code:String, /** A source map */ map:Dynamic
	},

	/** The compiled CSS */
	css:Null<{
		/** The generated code */
		code:String,
		/** A source map */
		map:Dynamic,
		/** Whether or not the CSS includes global rules */
		hasGlobal:Bool
	}>,

	/** An array of warning objects generated during compilation */
	warnings:Array<Dynamic>,

	/** Metadata about the compiled component */
	metadata:{
		/**
		 * Whether the file was compiled in runes mode.
		 * For compileModule, this is always true.
		 */
		runes:Bool
	},

	/** The AST */
	ast:Dynamic
}

#if dev
class SvelteRoute extends AbstractHandler {
	private var thisPathname:String;

	private var serverPage:Null<AbstractServerPage>;

	private var eTag:String = "";
	private var cachedPageSrc:{
		js:String,
		css:String
	} = {js: "", css: ""};

	public function new(serverPage:AbstractServerPage, thisPathname:String) {
		this.serverPage = serverPage;
		this.thisPathname = thisPathname;
	}

	private function compileIfNeeded(physicalPathname:String):{
		js:String,
		css:String
	} {
		var source = File.getContent(physicalPathname);
		var sourceTag = Sha1.encode(source);

		if (sourceTag == eTag) {
			return cachedPageSrc;
		}

		trace("ETag doesn't match! ", sourceTag + " vs " + eTag, " rebuilding!");

		var compileResult:SvelteCompileResult = NodeRunner.runNodeScript("sveltecc.js", {
			src: source,
			filename: thisPathname,
			preprocessorConfig: null,
			rootDir: FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, "src/"]))
		});

		var css = "";
		if (compileResult.css != null) {
			css = compileResult.css.code;
		}

		var pageSrc = {
			js: compileResult.js.code,
			css: css
		};

		cachedPageSrc = pageSrc;
		eTag = sourceTag;

		return pageSrc;
	}

	@:keep public function GET(event:RequestEvent) {
		var physicalPathname = Path.join([Configuration.WorkingDirectory, this.thisPathname]);
		if (!FileSystem.exists(physicalPathname)) {
			error(404, "File not found on disk: " + physicalPathname);
		}

		// TODO: implement Server Side Rendering
		var pageSrc = compileIfNeeded(physicalPathname);

		if (event.url.search.indexOf("script") != -1) {
			throw new HttpResponse(200, ["content-type" => "text/javascript; charset=utf-8"],
				Bytes.ofString(JavaScriptTransformer.transform(pageSrc.js, this.thisPathname)));
		}

		var appPage = File.getContent(Path.join([Configuration.WorkingDirectory, "src/app.html"]));

		var head = '<style>${pageSrc.css}</style>';
		var body = "";

		// TODO: make server page do something
		trace("AA: ", physicalPathname);

		body += '<script type="module">${JavaScriptTransformer.transform('import { mount } from "svelte";
		import App from ${Json.stringify(event.url.pathname + "?script=true")};

mount(App, {
	target: document.querySelector("#app-container"),
	props: ${Json.stringify(serverPage != null ?serverPage.pageServerLoad(event) : {})}
});',  this.thisPathname)}</script>';

		appPage = StringTools.replace(appPage, "%draconic.svelte.head%", head);
		appPage = StringTools.replace(appPage, "%draconic.svelte.body%", body);
		throw new HttpResponse(200, ["content-type" => "text/html"], Bytes.ofString(appPage));
	}
}
#end
