package server.util;

import haxe.io.Error;
import markdown.AST;

/**
	Translates a parsed AST to HTML.
**/
class XmlMarkdownRenderer implements NodeVisitor {
	static var BLOCK_TAGS = new EReg('blockquote|h1|h2|h3|h4|h5|h6|hr|p|pre', '');

	var root:Null<Xml>;

	var elementStack = new Array<Xml>();

	public function new() {}

	public function render(nodes:Array<Node>):Xml {
		root = Xml.createElement("div");
		root.set("class", "markdown");

		if (root != null)
			elementStack = [root];

		for (node in nodes)
			node.accept(this);

		// will never happen
		if (root == null)
			throw Error.Blocked;
		return root;
	}

	public function visitText(text:TextNode):Void {
		var thisRoot = elementStack[elementStack.length - 1];

		// please Haxe markdown, add an option to disable this!
		final unstupidify = (s:String) -> {
			s = StringTools.replace(s, "&lt;", "<");
			s = StringTools.replace(s, "&gt;", ">");
			s = StringTools.replace(s, "&amp;", "&");
			s = StringTools.replace(s, "&quot;", "\"");
			s = StringTools.replace(s, "&apos;", "'");
			s = StringTools.replace(s, "&equals;", "=");
			s = StringTools.replace(s, "&ne;", "≠");
			s = StringTools.replace(s, "&le;", "≤");
			s = StringTools.replace(s, "&ge;", "≥");
			s = StringTools.replace(s, "&plusmn;", "±");
			s = StringTools.replace(s, "&times;", "×");
			s = StringTools.replace(s, "&divide;", "÷");
			s = StringTools.replace(s, "&infin;", "∞");
			s = StringTools.replace(s, "&nbsp;", " ");
			s = StringTools.replace(s, "&ensp;", " ");
			s = StringTools.replace(s, "&emsp;", " ");
			s = StringTools.replace(s, "&thinsp;", " ");
			s = StringTools.replace(s, "&ndash;", "–");
			s = StringTools.replace(s, "&mdash;", "—");
			s = StringTools.replace(s, "&hellip;", "…");
			s = StringTools.replace(s, "&lsquo;", "‘");
			s = StringTools.replace(s, "&rsquo;", "’");
			s = StringTools.replace(s, "&ldquo;", "“");
			s = StringTools.replace(s, "&rdquo;", "”");
			s = StringTools.replace(s, "&euro;", "€");
			s = StringTools.replace(s, "&pound;", "£");
			s = StringTools.replace(s, "&yen;", "¥");
			s = StringTools.replace(s, "&cent;", "¢");
			s = StringTools.replace(s, "&copy;", "©");
			s = StringTools.replace(s, "&reg;", "®");
			s = StringTools.replace(s, "&trade;", "™");
			s = StringTools.replace(s, "&larr;", "←");
			s = StringTools.replace(s, "&uarr;", "↑");
			s = StringTools.replace(s, "&rarr;", "→");
			s = StringTools.replace(s, "&darr;", "↓");
			s = StringTools.replace(s, "&harr;", "↔");
			s = StringTools.replace(s, "&frac12;", "½");
			s = StringTools.replace(s, "&frac14;", "¼");
			s = StringTools.replace(s, "&frac34;", "¾");
			s = StringTools.replace(s, "&eacute;", "é");
			s = StringTools.replace(s, "&Eacute;", "É");
			s = StringTools.replace(s, "&agrave;", "à");
			s = StringTools.replace(s, "&auml;", "ä");
			s = StringTools.replace(s, "&ouml;", "ö");
			s = StringTools.replace(s, "&uuml;", "ü");
			s = StringTools.replace(s, "&ntilde;", "ñ");
			return s;
		};

		if (thisRoot != null)
			thisRoot.addChild(Xml.createCData(unstupidify(text.text)));
	}

	public function visitElementBefore(element:ElementNode):Bool {
		// Hackish. Separate block-level elements with newlines.
		/*if (buffer.toString() != "" && BLOCK_TAGS.match(element.tag)) {
			buffer.add('\n');
		}*/

		var thisElement = Xml.createElement(element.tag);

		var thisRoot = elementStack[elementStack.length - 1];
		if (thisRoot != null)
			thisRoot.addChild(thisElement);
		elementStack.push(thisElement);

		// Sort the keys so that we generate stable output.
		// TODO(rnystrom): This assumes keys returns a fresh mutable
		// collection.
		var attributeNames = [for (k in element.attributes.keys()) k];
		attributeNames.sort(sortAttributes);
		for (name in attributeNames) {
			var v = element.attributes.get(name);
			if (v != null)
				thisElement.set(name, v);
		}

		if (element.isEmpty()) {
			return false;
		} else {
			return true;
		}
	}

	public function visitElementAfter(element:ElementNode):Void {
		elementStack.pop();
	}

	static var attributeOrder = ['src', 'alt'];

	static function sortAttributes(a:String, b:String) {
		var ia = attributeOrder.indexOf(a);
		var ib = attributeOrder.indexOf(a);
		if (ia > -1 && ib > -1)
			return ia - ib;
		return Reflect.compare(a, b);
	}
}
