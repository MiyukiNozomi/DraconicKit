package server.util;

import shinku.std.URL;
import haxe.io.Path;
import sys.io.File;
import haxe.io.Error;
import server.routes.XHTMLRoute.PreprocessorFunc;

using StringTools;

class XmlProcessor {
	public static function process(xml:Xml, url:URL, pageProps:Dynamic, isDirectNavigation:Bool) {
		try {
			final scriptEngine = new HxScriptEngine(xml);
			processElements(scriptEngine, xml, pageProps, isDirectNavigation);
			scriptEngine.evaluateAll(url, isDirectNavigation);
			return xml;
		} catch (errr) {
			return Xml.createCData("Failed: " + errr.message + "\n" + errr.stack.toString());
		}
	}

	private static function applyProps(xml:Xml, props:Dynamic) {
		for (key in Reflect.fields(props)) {
			xml.set(key, Reflect.getProperty(props, key) + "");
		}
	}

	private static function processElements(scriptEngine:HxScriptEngine, node:Xml, pageProps:Dynamic, isDirectNavigation:Bool):Void {
		switch (node.nodeType) {
			case Xml.Element:
				if (node.nodeName.startsWith("builder:"))
					processBuilderElement(scriptEngine, node, pageProps, isDirectNavigation);
				if (node.nodeName == "script" && node.get("lang") == "hx") {
					applyProps(node, pageProps);
					scriptEngine.collect(node, XmlTools.getTextContent(node));
				}
			default:
		}

		if (node.nodeType == Document || node.nodeType == Element)
			for (child in node) {
				processElements(scriptEngine, child, pageProps, isDirectNavigation);
			}
	}

	private static function processBuilderElement(scriptEngine:HxScriptEngine, node:Xml, pageProps:Dynamic, isDirectNavigation:Bool):Void {
		switch (node.nodeName) {
			case "builder:markdown":
				{
					var xml = XmlTools.markdown2Xml(XmlTools.getTextContent(node));
					//	trace("Markdown as XML: ", xml);
					XmlTools.replaceWith(node, xml);
				}
			case "builder:import":
				{
					final src = node.get("src");

					if (src == null)
						throw Error.Custom("Import statement without src: " + node.toString());

					var currentProps = {};

					for (attrib in node.attributes()) {
						if (attrib.startsWith("set-")) {
							Reflect.setField(currentProps, attrib.substring(4), node.get(attrib));
						}
					}

					var content = File.getContent(Path.join([Main.SERVE_DIRECTORY, src]));

					var target;
					if (src.endsWith(".xhtml")) {
						try {
							target = Xml.parse(content);
							var children = new Array<Xml>();
							for (child in node.iterator()) {
								children.push(child);
							}

							if (children.length > 0) {
								var childrenHandler = XmlSelector.querySelector(target, "children");
								if (childrenHandler == null) {
									throw Error.Custom("Could not import file "
										+ src
										+ " because: it does not have a children tag on it (or remove the following content from builder:import)\n"
										+ children.toString());
								}
								for (child in children)
									processElements(scriptEngine, child, pageProps, isDirectNavigation);
								XmlTools.replaceWithAll(childrenHandler, children);
							}

							target = XmlProcessor.process(target, new URL(src, "http://0.0.0.0"), currentProps, isDirectNavigation && true);
						} catch (e) {
							throw Error.Custom("Could not parse file " + src + " because: " + e.message + "\n" + e.stack.toString());
						}
					} else if (src.endsWith(".svg")) {
						try {
							var nt = Xml.parse(content).firstElement();
							if (nt == null)
								throw Error.Custom("Bad SVG! no elements on it!");
							target = nt;
						} catch (e) {
							throw Error.Custom("Could not parse file " + src + " because: " + e.message + "\n" + e.stack.toString());
						}
					} else {
						final wrap = node.get("wrap");
						if (wrap == null) {
							throw Error.Custom("Import statement of non XHTML is missing 'wrap'.");
						}

						target = Xml.createElement(wrap);
						target.addChild(Xml.createCData(content));
					}
					if (target.nodeType == Element)
						applyProps(target, currentProps);
					XmlTools.replaceWith(node, target);
				}
			default:
				throw Error.Custom("Unknown builder derivative: " + node.toString());
		}
	}
}
