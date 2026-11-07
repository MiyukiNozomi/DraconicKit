package server.routes;

import haxe.io.Bytes;
import server.util.XmlProcessor;
import shinku.handling.AbstractHandler;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.http.HttpMessages.HttpResponse;
import sys.io.File;

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
			text(xml.toString(), {
				status: 200,
				headers: ["content-type" => contentType]
			});
		} catch (e) {
			if (Std.downcast(e, HttpResponse) != null)
				throw e;
			error(400, "SSR Failed for " + this.fullPath + " because: " + e.toString() + "\n" + e.stack.toString());
		}
	}
}
