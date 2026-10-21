package server;

import haxe.Exception;
import haxe.Json;
import haxe.Rest;
import haxe.io.Error;
import haxe.io.Path;
import js.html.HtmlElement;
import js.html.NamedNodeMap;
import node_html_parser.parse.HTMLElement;
import node_html_parser.parse.Node;
import shinku.std.MimeTypes;
import sys.FileSystem;
import sys.io.File;

using StringTools;

typedef HandlerFunc = (e:HTMLElement, customHandlers:Map<String, HandlerFunc>, thisURL:String) -> Void;

class HTMLTransformer {
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
					transformElement(thisURL, elm, customHandlers);
					applyAttributes(elm, attrs);
				}
				renderElement(html, elements);
			} else if (isScript) {
				var script = NodeHtmlParser.parse('<script>$txt</script>');
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

	public static function renderElement(target:HTMLElement, elements:Array<HTMLElement>) {
		if (elements.length == 0) {
			target.remove();
			return;
		}

		var divider = new HTMLElement("", {});
		for (elm in elements)
			divider.appendChild(elm);
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
		for (h1 in elm.querySelectorAll("h1")) {
			h1.id = slugify(h1.textContent);
		}
		for (h2 in elm.querySelectorAll("h2")) {
			h2.id = slugify(h2.textContent);
		}

		elm.classList.add("markdown");
		return elm;
	}

	public static function transformElement(thisURL:String, root:HTMLElement, customHandlers:Map<String, HandlerFunc>) {
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
					showError(e, result);
				}
			}
		};

		for (key => clb in customHandlers)
			runTransformer(key, clb);

		for (key => clb in thisHandlers)
			runTransformer(key, clb);

		var interp = new hscript.Interp();

		interp.variables.set("Math", Math);
		interp.variables.set("Path", Path);
		interp.variables.set("Json", Json);

		interp.variables.set("File", {
			getContent: (s:String) -> return File.getContent(s),
		});

		interp.variables.set("FileSystem", {
			readDirectory: (s:String) -> return FileSystem.readDirectory(s),
			isDirectory: (s:String) -> return FileSystem.isDirectory(s),
			exists: (s:String) -> return FileSystem.exists(s),
		});

		interp.variables.set("document", {
			createElement: (name:String, children:Null<Array<HTMLElement>>) -> {
				var elm = new HTMLElement(name, {});
				if (children != null) {
					for (child in children) {
						elm.appendChild(child);
					}
				}
				return elm;
			},
			parse: (src:String) -> return NodeHtmlParser.parse(src),
			parseMarkdown: (src:String) -> return parseMarkdownToHTML(src),
		});

		var scripts = root.getElementsByTagName('script');

		for (elm in scripts) {
			try {
				if (elm.attributes.exists("hmr"))
					continue;

				if (elm.attributes.get("lang") != "hx") {
					throw Error.Custom("You have a non-hscript script tag: " + elm.toString() + ". This website should not have runtime JS.");
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

				renderElement(elm, elementsToRender);
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
