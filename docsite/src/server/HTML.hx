package server;

import hscript.Interp;
import haxe.Exception;
import haxe.Json;
import haxe.io.Error;
import haxe.io.Path;
import node_html_parser.parse.HTMLElement;
import shinku.std.MimeTypes;
import sys.FileSystem;
import sys.io.File;

using StringTools;

typedef HandlerFunc = (e:HTMLElement, customHandlers:Map<String, HandlerFunc>, thisURL:String) -> Void;

class HTMLTransformer {
	private static final scriptGlobals:Map<String, Dynamic> = [
		"Math" => Math,
		"Path" => Path,
		"Json" => Json,
		"StringTools" => StringTools,
		"File" => {
			getContent: (s:String) -> return File.getContent(s),
		},
		"FileSystem" => {
			readDirectory: (s:String) -> return FileSystem.readDirectory(s),
			isDirectory: (s:String) -> return FileSystem.isDirectory(s),
			exists: (s:String) -> return FileSystem.exists(s),
		},
	];

	private static function createDocument(interp:Interp, root:HTMLElement, attribs:Null<Map<String, String>>) {
		interp.variables.set("document", {
			getRootNode: () -> {
				return root;
			},
			getRootAttributes: () -> {
				return attribs != null ? attribs : new Map();
			},
			createElement: (name:String, children:Null<Array<HTMLElement>>) -> {
				var elm = new HTMLElement(name, {});
				if (children != null) {
					for (child in children) {
						elm.appendChild(child);
					}
				}
				return elm;
			},
			querySelector: (tag:String) -> return root.querySelector(tag),
			querySelectorAll: (tag:String) -> return root.querySelectorAll(tag),
			parse: (src:String) -> return NodeHtmlParser.parse(src),
			parseMarkdown: (src:String) -> return parseMarkdownToHTML(src),
		});
	}

	private static function collectSetAttributes(html:HTMLElement):Map<String, String> {
		var result = new Map<String, String>();
		for (attrib in html.attributes.keys()) {
			if (StringTools.startsWith(attrib, "set-")) {
				result.set(attrib.substring(4), html.attributes.get(attrib) + "");
			}
		}
		return result;
	}

	private static function parseElements(markup:String, src:String) {
		var root = NodeHtmlParser.parse(markup);
		var elements = root.children;
		if (elements == null || elements.length == 0) {
			throw "Imported file has no root element: " + src;
		}
		return elements;
	}

	private static var thisHandlers:Map<String, HandlerFunc> = [
		"import" => (html, customHandlers, thisURL) -> {
			final applyAttributes = (target:HTMLElement, attrs:Map<String, String>) -> {
				for (key => value in attrs)
					target.setAttribute(key, value);
			};
			var src = html.attributes.get("src");
			if (src == null) {
				throw "builder:import tag is missing 'src'.";
			}
			var enclosingTag = html.attributes.get("wrap");
			if (enclosingTag == null)
				enclosingTag = "";
			var attrs = collectSetAttributes(html);
			var path = Path.join([Main.SERVE_DIRECTORY, src]);
			var txt:String;
			try {
				txt = File.getContent(path);
			} catch (e:Dynamic) {
				throw "Could not read file '" + path + "': " + Std.string(e);
			}
			var mimeType = MimeTypes.forFilename(path);
			var isMarkup = (mimeType == "text/html" || mimeType == "image/svg+xml");
			var isScript = (mimeType == "text/javascript" || mimeType == "application/javascript");
			if (enclosingTag.length > 0) {
				var wrapper = new HTMLElement(enclosingTag, {});
				applyAttributes(wrapper, attrs);
				if (isMarkup) {
					wrapper.appendChild(transformHTML(thisURL, src, customHandlers, txt));
				} else {
					wrapper.textContent = txt;
				}
				html.replaceWith(wrapper);
			} else if (isMarkup) {
				var elements = parseElements(txt, src);
				for (elm in elements) {
					transformElement(thisURL, elm, customHandlers, attrs);
					applyAttributes(elm, attrs);
				}
				var children = new HTMLElement("div", {});
				for (childNode in html.childNodes.copy())
					children.appendChild(childNode);
				transformElement(thisURL, children, customHandlers, attrs);
				renderElement(thisURL, html, elements, children);
			} else if (isScript) {
				var script = new HTMLElement("script", {});
				script.textContent = txt;
				applyAttributes(script, attrs);
				html.replaceWith(script);
			} else {
				throw "Cannot import without an enclosing tag: " + src;
			}
		},
		"markdown" => (html, ch, _) -> {
			applyMarkdownFor(html, StringTools.trim(html.textContent));
		}
	];

	public static function renderElement(pathname:String, target:HTMLElement, elements:Array<HTMLElement>, ?placeholder:HTMLElement) {
		if (elements.length == 0) {
			target.remove();
			return;
		}
		var divider = new HTMLElement("", {});
		for (elm in elements)
			divider.appendChild(elm);
		var placeholderTargets = divider.querySelectorAll("builder\\:children");
		if (placeholderTargets.length > 1)
			throw "Multiple builder\\:children tags found in " + pathname + ". Can only have one per imported component.";
		if (placeholder != null) {
			if (placeholderTargets.length > 0) {
				placeholderTargets[0].replaceWith(placeholder);
			}
		} else {
			for (t in placeholderTargets) {
				t.remove();
			}
		}
		target.replaceWith(divider);
	}

	public static function slugify(text:String) {
		var result = text.toLowerCase();
		result = StringTools.trim(result);
		result = ~/\s+/g.replace(result, "-");
		result = ~/[^a-z0-9-]/g.replace(result, "");
		result = ~/-+/g.replace(result, "-");
		result = ~/^-|-$/g.replace(result, "");
		return result;
	}

	public static function parseMarkdownToHTML(text:String) {
		var newHtml = Markdown.markdownToHtml(text);
		var elm = new HTMLElement("div", {});
		elm.appendChild(NodeHtmlParser.parse(newHtml));
		// a small transformation is needed here because haxe markdown doesnt put ids by default.
		for (h in elm.querySelectorAll("h1, h2, h3")) {
			if (h.id == "")
				h.id = slugify(h.textContent);
		}
		elm.classList.add("markdown");
		return elm;
	}

	public static function transformElement(thisURL:String, root:HTMLElement, customHandlers:Map<String, HandlerFunc>, ?attribs:Map<String, String>) {
		final showError = (e:Exception, result:HTMLElement) -> {
			//	value.innerText = "Could not preprocess this tag " + value.toString() + " because: " + JSON.stringify(e);
			final err = new HTMLElement("p", {});
			err.setAttribute("style",
				'position: fixed; left: 50%; width:80%; transform: translateX(-50%); top:4rem; z-index: 50; background-color: #0f0f0f; color:#ff0000; border:4px solid #ff0a0a; padding: 6px 6px;');
			err.textContent = "Transformation failed for tag " + result.tagName + " because: " + e.toString();
			result.replaceWith(err);
		};
		final runTransformer = (key:String, fn:HandlerFunc) -> {
			var results = root.querySelectorAll('builder\\:$key');
			for (result in results) {
				try {
					fn(result, customHandlers, thisURL);
				} catch (e) {
					trace(e);
					trace(e.stack);
					showError(e, result);
				}
			}
		};
		for (key => clb in customHandlers)
			runTransformer(key, clb);
		for (key => clb in thisHandlers)
			runTransformer(key, clb);
		var interp = new hscript.Interp();
		for (k => v in scriptGlobals)
			interp.variables.set(k, v);
		createDocument(interp, root, attribs);
		var scripts = root.getElementsByTagName('script');
		for (elm in scripts) {
			try {
				if (elm.attributes.exists("hmr"))
					continue;

				if (elm.attributes.get("lang") != "hx") {
					throw Error.Custom("You have a non-hscript script tag: "
						+ elm.toString()
						+ ". Thou shall not spread your wicked ways on our holy draconic land.");
				}
				var parser = new hscript.Parser();
				var program = parser.parseString(elm.textContent);
				var elementsToRender = new Array<HTMLElement>();
				interp.variables.set("builder", {
					thisURL: () -> {
						return thisURL;
					},
					slugify: (str:String) -> return slugify(str),
					getWorkdir: () -> return Main.SERVE_DIRECTORY,
					render: (e:Null<HTMLElement>) -> {
						e != null ? elementsToRender.push(e) : {};
						return e;
					}
				});
				interp.execute(program);
				renderElement(thisURL, elm, elementsToRender);
			} catch (e) {
				trace(e);
				showError(e, elm);
			}
		}
		return root;
	}

	public static function applyMarkdownFor(html:HTMLElement, text:String) {
		var elm = parseMarkdownToHTML(text);
		for (value in html.classList.value)
			elm.classList.add(value);
		html.replaceWith(elm);
	}

	public static function transformHTML(thisURL:String, filePath:String, customHandlers:Map<String, HandlerFunc>, ?customSrc:Null<String>) {
		final root = NodeHtmlParser.parse(customSrc == null ? File.getContent(filePath) : customSrc);
		return transformElement(thisURL, root, customHandlers);
	}
}
