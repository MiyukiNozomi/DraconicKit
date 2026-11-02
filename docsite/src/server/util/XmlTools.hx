package server.util;

import haxe.Exception;
import Markdown.Document;
import haxe.io.Error;

class XmlTools {
	public static function markdown2Xml(markdown:String) {
		var document = new Document();
		try {
			// replace windows line endings with unix, and split
			var lines = ~/(\r\n|\r)/g.replace(markdown, '\n').split("\n");
			// parse ref links
			document.parseRefLinks(lines);
			// parse ast
			var blocks = document.parseLines(lines);
			return new XmlMarkdownRenderer().render(blocks);
		} catch (e) {
			throw new Exception("Markdown failed! " + e.message + " \n at: " + e.stack.toString());
		}
	}

	static function flattenDocuments(nodes:Array<Xml>, ?out:Array<Xml>):Array<Xml> {
		if (out == null)
			out = [];
		for (n in nodes) {
			if (n.nodeType == Xml.Document)
				flattenDocuments([for (c in n) c], out);
			else
				out.push(n);
		}
		return out;
	}

	public static function replaceWith(node:Xml, replacement:Xml):Int {
		return replaceWithAll(node, [replacement]);
	}

	static function indexOfChild(parent:Xml, child:Xml):Int {
		var i = 0;
		for (c in parent.iterator()) {
			if (c == child)
				return i;
			i++;
		}
		return -1;
	}

	public static function replaceWithAll(node:Xml, elements:Array<Xml>):Int {
		final parent = node.parent;
		if (parent == null)
			throw Error.Custom("Cannot replace a node without a parent.");

		final flat = flattenDocuments(elements);
		final start = indexOfChild(parent, node);

		for (el in flat) {
			if (el == node)
				continue;
			// only needed so an earlier sibling can't shift node's index
			if (el.parent != null)
				el.parent.removeChild(el);
			parent.insertChild(el, indexOfChild(parent, node));
		}

		parent.removeChild(node);
		return start;
	}

	public static function slugify(text:String):String {
		var result = text.toLowerCase();
		result = StringTools.trim(result);
		result = ~/\s+/g.replace(result, "-");
		result = ~/[^a-z0-9-]/g.replace(result, "");
		result = ~/-+/g.replace(result, "-");
		result = ~/^-|-$/g.replace(result, "");
		return result;
	}

	public static function getTextContent(node:Xml):String {
		var result = new StringBuf();

		switch (node.nodeType) {
			case Xml.PCData, Xml.CData:
				result.add(node.nodeValue);

			case Xml.Document, Xml.Element:
				for (child in node) {
					result.add(getTextContent(child));
				}

			default:
		}

		return result.toString();
	}
}
