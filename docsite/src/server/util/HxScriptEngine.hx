package server.util;

import server.routes.apiref.JavadocHandler;
import haxe.crypto.Base64;
import haxe.Json;
import shinku.std.URL;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import hscript.Parser;
import hscript.Interp;
import haxe.io.Error;

typedef CollectedScript = {
	script:String,
	priority:Int,
	xml:Xml
};

class HxScriptEngine {
	private var collectedScripts:Array<CollectedScript>;
	private var rootNode:Xml;

	public function new(rootNode:Xml) {
		this.collectedScripts = new Array();
		this.rootNode = rootNode;
	}

	public function collect(xml:Xml, src:String) {
		var priority = Std.parseInt(xml.get("priority") ?? "-1");
		if (priority == null)
			throw Error.Custom("Script tag has a bad 'priority'!" + xml.toString());

		this.collectedScripts.push({
			xml: xml,
			priority: priority,
			script: src
		});
	}

	public function evaluateAll(thisURL:URL, isDirectNavigation:Bool) {
		collectedScripts.sort((a, b) -> {
			return b.priority - a.priority;
		});

		var interp = new Interp();

		registerBuiltIns(interp, thisURL);

		for (scr in this.collectedScripts) {
			if (scr.xml.parent == null) {
				//		trace("script was detached by an earlier script, skipping:", scr.xml.toString());
				continue;
			}

			try {
				if (scr.xml.get("lang") != "hx") {
					throw Error.Custom("You have a non-hscript script tag: "
						+ scr.xml.toString()
						+ ". Thou shall not spread your wicked ways on our holy draconic land.");
				}
				var parser = new Parser();
				var program = parser.parseString(scr.script);
				if (program == null) {
					throw Error.Custom("Parser failed!");
				}

				var scriptThis = registerScriptLocals(interp, scr, isDirectNavigation);
				interp.execute(program);
				XmlTools.replaceWithAll(scr.xml, scriptThis.renderElements);
			} catch (e) {
				var err = Xml.createElement("pre");
				err.set("class", "floating-error");

				var header = Xml.createElement("h1");
				header.addChild(Xml.createCData("SERVER SIDE RENDERING HAS FAILED!"));
				err.addChild(header);
				err.addChild(Xml.createCData("in URL: "
					+ thisURL.toString()
					+ "\nScript source: "
					+ (scr.xml.parent != null && scr.xml.nodeType == Element ? scr.xml.parent.nodeName : scr.xml.toString())
					+ "\nException reason: "
					+ e.message
					+ "\n\nStack trace:\n"
					+ e.stack.toString()));
				XmlTools.replaceWith(scr.xml, err);
			}
		}
	}

	private function registerScriptLocals(interp:Interp, scr:CollectedScript, isDirectNavigation:Bool) {
		var renderElements = new Array<Xml>();
		var props = {};
		for (attrib in scr.xml.attributes()) {
			var v = scr.xml.get(attrib) + "";

			if (StringTools.startsWith(v, "object:")) {
				Reflect.setProperty(props, attrib, Json.parse(Base64.urlDecode(v.substring("object:".length)).toString()));
			} else {
				Reflect.setProperty(props, attrib, v);
			}
		}

		var scriptThis = {
			"append": (s:Xml) -> {
				if (s == null)
					throw Error.Custom("Cannot append a *null* element!");
				renderElements.push(s);
				return s;
			},
			"props": props,
			"scriptNode": scr.xml,
			"isDirectNavigation": isDirectNavigation,
		};
		interp.variables.set("renderer", scriptThis);
		return {
			renderElements: renderElements,
			object: scriptThis
		};
	}

	private function registerBuiltIns(interp:Interp, thisURL:URL) {
		interp.variables.set("Path", Path);
		interp.variables.set("Std", Std);
		interp.variables.set("FileSystem", FileSystem);
		interp.variables.set("Json", {
			"parse": (s:String) -> return Json.parse(s),
			"stringify": (s:Dynamic) -> return Json.stringify(s)
		});
		interp.variables.set("Reflect", Reflect);
		interp.variables.set("File", File);
		interp.variables.set("Server", {
			"getPageXML": (url:String) -> {
				var nd = XmlProcessor.process(Xml.parse(File.getContent(Path.join([Main.SERVE_DIRECTORY, url]))), new URL(url, "http://localhost/"), [], false);
				return nd;
			}
		});
		interp.variables.set("JavaDoc", {
			parse: (s:String) -> return new JavadocHandler().parse("<idk>", s ?? "")
		});

		interp.variables.set("document", {
			"location": thisURL,
			"markdownAsXML": (mk:String) -> return XmlTools.markdown2Xml(mk),
			"workdir": () -> return Main.SERVE_DIRECTORY,

			"root": this.rootNode,

			"slugify": (text:String) -> XmlTools.slugify(text),

			"debugPrint": (xml:Xml) -> {
				var recursivePrint;
				recursivePrint = (xml:Xml, indent:String) -> {
					trace(indent, xml.nodeType == Element ? xml.nodeName : "no-tag (not an element)", xml.nodeType);
					if (xml.nodeType == Element || xml.nodeType == Document) {
						for (nd in xml)
							recursivePrint(nd, indent + " ");
					}
				};

				recursivePrint(xml, "");
			},

			"createElement": (s:String) -> return Xml.createElement(s),
			"createElementWithAttribs": (s:String, d:Dynamic) -> {
				var nd = Xml.createElement(s);
				for (key in Reflect.fields(d)) {
					nd.set(key, Reflect.getProperty(d, key) + "");
				}
				return nd;
			},
			"createCData": (s:String) -> return Xml.createCData(s + ""),
			"getTextContents": (xml:Xml) -> return XmlTools.getTextContent(xml),

			"replaceElement": (dst:Xml, replacement:Xml) -> {
				return XmlTools.replaceWith(dst, replacement);
			},

			"getChildNodes": (x:Xml) -> {
				if (x == null)
					throw Error.Custom("getChildNodes received NULL instead of a Node!");
				var nd = new Array<Xml>();
				for (n in x) {
					nd.push(n);
				}
				return nd;
			},
			"querySelector": (s:String) -> return XmlSelector.querySelector(this.rootNode, s),

			"querySelectorAll": (s:String) -> return XmlSelector.querySelectorAll(this.rootNode, s),
			"querySelectorWithin": (xml:Xml, s:String) -> return XmlSelector.querySelector(xml, s),
			"querySelectorAllWithin": (xml:Xml, s:String) -> return XmlSelector.querySelectorAll(xml, s),
		});
	}
}
