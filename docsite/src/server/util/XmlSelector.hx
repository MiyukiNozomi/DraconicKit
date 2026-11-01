/***
	Did not implement this (I stole it!)
**/

package server.util;

import StringTools;

enum Combinator {
	Descendant; // a b
	Child; // a > b
	Adjacent; // a + b
	Sibling; // a ~ b
}

enum AttrOp {
	Exists; // [a]
	Equals; // [a=v]
	Includes; // [a~=v]
	DashMatch; // [a|=v]
	Prefix; // [a^=v]
	Suffix; // [a$=v]
	Substring; // [a*=v]
}

typedef AttrSel = {
	name:String,
	op:AttrOp,
	value:String,
	ci:Bool
};

enum Pseudo {
	Nth(a:Int, b:Int, fromEnd:Bool, ofType:Bool);
	Empty;
	Root;
	Not(list:Array<Array<Step>>);
	Is(list:Array<Array<Step>>);
}

typedef Compound = {
	tag:Null<String>,
	ids:Array<String>,
	classes:Array<String>,
	attrs:Array<AttrSel>,
	pseudos:Array<Pseudo>
};

typedef Step = {
	combinator:Combinator,
	compound:Compound
};

class XmlSelector {
	public static function querySelector(root:Xml, selector:String):Null<Xml> {
		var list = new SelectorParser(selector).parse();
		var found:Null<Xml> = null;
		walk(root, function(n) {
			if (matchesList(n, list)) {
				found = n;
				return true;
			}
			return false;
		});
		return found;
	}

	public static function querySelectorAll(root:Xml, selector:String):Array<Xml> {
		var list = new SelectorParser(selector).parse();
		var results:Array<Xml> = [];
		walk(root, function(n) {
			if (matchesList(n, list))
				results.push(n);
			return false;
		});
		return results;
	}

	public static function matches(node:Xml, selector:String):Bool {
		return matchesList(node, new SelectorParser(selector).parse());
	}

	static function walk(node:Xml, f:Xml->Bool):Bool {
		for (child in node.elements()) {
			if (f(child) || walk(child, f))
				return true;
		}
		return false;
	}

	static function parentElement(node:Xml):Null<Xml> {
		var p = node.parent;
		return (p != null && p.nodeType == Xml.Element) ? p : null;
	}

	static function elementSiblings(node:Xml):Array<Xml> {
		var p = node.parent;
		if (p == null)
			return [node];
		return [for (e in p.elements()) e];
	}

	static function matchesList(node:Xml, list:Array<Array<Step>>):Bool {
		if (node.nodeType != Xml.Element)
			return false;
		for (steps in list) {
			if (matchComplex(node, steps, steps.length - 1))
				return true;
		}
		return false;
	}

	static function matchComplex(node:Xml, steps:Array<Step>, idx:Int):Bool {
		var step = steps[idx];
		if (!matchesCompound(node, step.compound))
			return false;
		if (idx == 0)
			return true;

		switch (step.combinator) {
			case Child:
				var p = parentElement(node);
				return p != null && matchComplex(p, steps, idx - 1);

			case Descendant:
				var p = parentElement(node);
				while (p != null) {
					if (matchComplex(p, steps, idx - 1))
						return true;
					p = parentElement(p);
				}
				return false;

			case Adjacent:
				var sibs = elementSiblings(node);
				var i = sibs.indexOf(node);
				return i > 0 && matchComplex(sibs[i - 1], steps, idx - 1);

			case Sibling:
				var sibs = elementSiblings(node);
				var i = sibs.indexOf(node);
				for (j in 0...i) {
					if (matchComplex(sibs[j], steps, idx - 1))
						return true;
				}
				return false;
		}
	}

	static var WS = ~/\s+/g;

	static function words(s:Null<String>):Array<String> {
		if (s == null)
			return [];
		return WS.split(StringTools.trim(s)).filter(function(w) return w != "");
	}

	static function matchesCompound(node:Xml, c:Compound):Bool {
		if (c.tag != null && c.tag != "*" && node.nodeName != c.tag)
			return false;

		for (id in c.ids) {
			if (node.get("id") != id)
				return false;
		}

		if (c.classes.length > 0) {
			var have = words(node.get("class"));
			for (cls in c.classes) {
				if (have.indexOf(cls) == -1)
					return false;
			}
		}

		for (a in c.attrs) {
			if (!matchesAttr(node, a))
				return false;
		}

		for (p in c.pseudos) {
			if (!matchesPseudo(node, p))
				return false;
		}

		return true;
	}

	static function matchesAttr(node:Xml, a:AttrSel):Bool {
		if (!node.exists(a.name))
			return false;

		var v = node.get(a.name) ?? "";
		var want = a.value;
		if (a.ci) {
			v = v.toLowerCase();
			want = want.toLowerCase();
		}

		return switch (a.op) {
			case Exists: true;
			case Equals: v == want;
			case Includes: want != "" && words(v).indexOf(want) != -1;
			case DashMatch: v == want || StringTools.startsWith(v, want + "-");
			case Prefix: want != "" && StringTools.startsWith(v, want);
			case Suffix: want != "" && StringTools.endsWith(v, want);
			case Substring: want != "" && v.indexOf(want) != -1;
		}
	}

	static function matchesPseudo(node:Xml, p:Pseudo):Bool {
		switch (p) {
			case Not(list):
				return !matchesList(node, list);

			case Is(list):
				return matchesList(node, list);

			case Root:
				return node.parent == null || node.parent.nodeType == Xml.Document;

			case Empty:
				for (child in node) {
					switch (child.nodeType) {
						case Xml.Element:
							return false;
						case Xml.PCData, Xml.CData:
							if (StringTools.trim(child.nodeValue) != "") return false;
						default:
					}
				}
				return true;

			case Nth(a, b, fromEnd, ofType):
				var sibs = elementSiblings(node);
				if (ofType)
					sibs = sibs.filter(function(s) return s.nodeName == node.nodeName);
				if (fromEnd)
					sibs.reverse();
				var pos = sibs.indexOf(node) + 1;
				return nthMatches(a, b, pos);
		}
	}

	static function nthMatches(a:Int, b:Int, pos:Int):Bool {
		if (a == 0)
			return pos == b;
		var diff = pos - b;
		if (diff % a != 0)
			return false;
		return diff == 0 || (diff > 0) == (a > 0);
	}
}

private class SelectorParser {
	var src:String;
	var pos:Int = 0;

	public function new(src:String) {
		this.src = src;
	}

	public function parse():Array<Array<Step>> {
		var list = parseList();
		if (pos < src.length)
			fail("unexpected '" + peek() + "'");
		return list;
	}

	function fail(msg:String):Dynamic {
		return throw 'Invalid selector "$src": $msg (at position $pos)';
	}

	inline function peek():String {
		return src.charAt(pos);
	}

	inline function eof():Bool {
		return pos >= src.length;
	}

	function expect(c:String) {
		if (peek() != c)
			fail("expected '" + c + "'");
		pos++;
	}

	/** Skips whitespace; returns true if any was skipped. */
	function ws():Bool {
		var start = pos;
		while (!eof() && StringTools.isSpace(src, pos))
			pos++;
		return pos > start;
	}

	static function isIdentChar(code:Int):Bool {
		return (code >= 'a'.code && code <= 'z'.code)
			|| (code >= 'A'.code && code <= 'Z'.code)
			|| (code >= '0'.code && code <= '9'.code)
			|| code == '_'.code
			|| code == '-'.code
			|| code > 127;
	}

	static function isIdentStart(code:Int):Bool {
		return !(code >= '0'.code && code <= '9'.code) && isIdentChar(code);
	}

	/** `extra` additionally allows ':' and '.' (valid in XML attribute names). */
	function ident(extra:Bool):String {
		var b = new StringBuf();
		var n = 0;
		while (!eof()) {
			var ch = peek();
			var code = src.charCodeAt(pos) ?? 0;
			if (ch == "\\") {
				pos++;
				if (eof())
					fail("dangling escape");
				b.add(peek());
				pos++;
				n++;
			} else if (isIdentChar(code) || (extra && (ch == ":" || ch == "."))) {
				b.add(ch);
				pos++;
				n++;
			} else {
				break;
			}
		}
		if (n == 0)
			fail("expected identifier");
		return b.toString();
	}

	function parseList():Array<Array<Step>> {
		var list = [];
		while (true) {
			list.push(parseComplex());
			ws();
			if (peek() == ",") {
				pos++;
				continue;
			}
			break;
		}
		return list;
	}

	function parseComplex():Array<Step> {
		var steps:Array<Step> = [];
		var comb = Descendant;
		ws();

		while (true) {
			steps.push({combinator: comb, compound: parseCompound()});

			var hadSpace = ws();
			var c = peek();
			if (c == "" || c == "," || c == ")")
				break;

			switch (c) {
				case ">":
					comb = Child;
					pos++;
					ws();
				case "+":
					comb = Adjacent;
					pos++;
					ws();
				case "~":
					comb = Sibling;
					pos++;
					ws();
				default:
					if (!hadSpace)
						fail("unexpected '" + c + "'");
					comb = Descendant;
			}
		}
		return steps;
	}

	function parseCompound():Compound {
		var c:Compound = {
			tag: null,
			ids: [],
			classes: [],
			attrs: [],
			pseudos: []
		};
		var any = false;

		while (!eof()) {
			var ch = peek();
			if (ch == "*") {
				if (any)
					fail("unexpected '*'");
				pos++;
				c.tag = "*";
			} else if (ch == "#") {
				pos++;
				c.ids.push(ident(false));
			} else if (ch == ".") {
				pos++;
				c.classes.push(ident(false));
			} else if (ch == "[") {
				c.attrs.push(parseAttr());
			} else if (ch == ":") {
				for (p in parsePseudo())
					c.pseudos.push(p);
			} else if (!any && (isIdentStart(src.charCodeAt(pos) ?? 0) || ch == "\\")) {
				c.tag = ident(false);
			} else {
				break;
			}
			any = true;
		}

		if (!any)
			fail("expected a selector");
		return c;
	}

	function parseAttr():AttrSel {
		expect("[");
		ws();
		var name = ident(true);
		ws();

		var op = Exists;
		var value = "";
		var ci = false;

		if (peek() != "]") {
			if (peek() == "=") {
				op = Equals;
				pos++;
			} else {
				op = switch (src.substr(pos, 2)) {
					case "~=": Includes;
					case "|=": DashMatch;
					case "^=": Prefix;
					case "$=": Suffix;
					case "*=": Substring;
					default: fail("invalid attribute operator");
				}
				pos += 2;
			}
			ws();
			value = parseValue();
			ws();
			if (peek() == "i" || peek() == "I") {
				ci = true;
				pos++;
				ws();
			}
		}

		expect("]");
		return {
			name: name,
			op: op,
			value: value,
			ci: ci
		};
	}

	function parseValue():String {
		var q = peek();
		var b = new StringBuf();

		if (q == "\"" || q == "'") {
			pos++;
			while (true) {
				if (eof())
					fail("unterminated string");
				var ch = peek();
				pos++;
				if (ch == q)
					break;
				if (ch == "\\") {
					if (eof())
						fail("unterminated string");
					ch = peek();
					pos++;
				}
				b.add(ch);
			}
			return b.toString();
		}

		var n = 0;
		while (!eof() && peek() != "]" && !StringTools.isSpace(src, pos)) {
			if (peek() == "\\")
				pos++;
			b.add(peek());
			pos++;
			n++;
		}
		if (n == 0)
			fail("expected attribute value");
		return b.toString();
	}

	function parsePseudo():Array<Pseudo> {
		expect(":");
		if (peek() == ":")
			fail("pseudo-elements are not supported");
		var name = ident(false).toLowerCase();

		if (peek() == "(") {
			pos++;
			switch (name) {
				case "not", "is", "matches":
					var list = parseList();
					ws();
					expect(")");
					return [name == "not" ? Not(list) : Is(list)];

				case "nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type":
					var start = pos;
					while (!eof() && peek() != ")")
						pos++;
					var ab = parseNth(src.substring(start, pos));
					expect(")");
					return [Nth(ab.a, ab.b, name.indexOf("last") != -1, name.indexOf("of-type") != -1)];

				default:
					fail("unsupported pseudo-class ':" + name + "()'");
			}
		}

		return switch (name) {
			case "first-child": [Nth(0, 1, false, false)];
			case "last-child": [Nth(0, 1, true, false)];
			case "only-child": [Nth(0, 1, false, false), Nth(0, 1, true, false)];
			case "first-of-type": [Nth(0, 1, false, true)];
			case "last-of-type": [Nth(0, 1, true, true)];
			case "only-of-type": [Nth(0, 1, false, true), Nth(0, 1, true, true)];
			case "empty": [Empty];
			case "root": [Root];
			default: fail("unsupported pseudo-class ':" + name + "'");
		}
	}

	function parseNth(raw:String):{a:Int, b:Int} {
		var s = StringTools.replace(StringTools.trim(raw).toLowerCase(), " ", "");
		if (s == "odd")
			return {a: 2, b: 1};
		if (s == "even")
			return {a: 2, b: 0};

		var n = s.indexOf("n");
		if (n == -1) {
			var b = toInt(s);
			if (b == null)
				fail("invalid an+b expression '" + raw + "'");
			return {a: 0, b: b ?? 0};
		}

		var aStr = s.substr(0, n);
		var bStr = s.substr(n + 1);

		var a:Null<Int> = (aStr == "" || aStr == "+") ? 1 : (aStr == "-") ? -1 : toInt(aStr);
		var b:Null<Int> = (bStr == "") ? 0 : toInt(bStr);
		if (a == null || b == null)
			fail("invalid an+b expression '" + raw + "'");
		return {a: a ?? 0, b: b ?? 0};
	}

	static function toInt(s:String):Null<Int> {
		if (StringTools.startsWith(s, "+"))
			s = s.substr(1);
		if (!~/^-?[0-9]+$/.match(s))
			return null;
		return Std.parseInt(s);
	}
}
