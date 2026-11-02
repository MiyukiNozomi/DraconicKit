package server.routes;

import server.util.XmlProcessor;
import server.util.XmlTools;
import server.util.HxScriptEngine;
import haxe.Exception;
import Markdown.Document;
import haxe.Json;
import haxe.io.Path;
import haxe.io.Error;
import haxe.io.Bytes;
import sys.io.File;
import shinku.std.MimeTypes;
import shinku.http.HttpMessages.HttpResponse;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.handling.AbstractHandler;
import server.util.XmlMarkdownRenderer;

using StringTools;

typedef PreprocessorFunc = (node:Xml, custom:Map<String, PreprocessorFunc>) -> Void;

class XHTMLRoute extends AbstractHandler {
	private var fullPath:String;
	private var customProps:Dynamic;

	public function new(fp, props = {}) {
		super();
		this.fullPath = fp;
		this.customProps = props;
	}

	public function GET(event:RequestEvent) {
		try {
			final contentType = "application/xhtml+xml";
			var xml = XmlProcessor.process(Xml.parse(File.getContent(this.fullPath)), event.url, customProps, true);
			throw new HttpResponse(200, ["content-type" => contentType], Bytes.ofString(xml.toString()));
		} catch (e) {
			if (Std.downcast(e, HttpResponse) != null)
				throw e;
			error(400, "SSR Failed for " + this.fullPath + " because: " + e.toString() + "\n" + e.stack.toString());
		}
	}
}
