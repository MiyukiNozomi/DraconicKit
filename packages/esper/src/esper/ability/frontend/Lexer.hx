package esper.ability.frontend;

import esper.ability.frontend.Parser.ParseError;
import esper.ability.frontend.Token.Token;
import esper.ability.frontend.Token.TokenType;

class Lexer {
	static final KEYWORDS:Array<String> = [
		"break",
		"case",
		"catch",
		"class",
		"const",
		"continue",
		"debugger",
		"default",
		"delete",
		"do",
		"else",
		"enum",
		"export",
		"extends",
		"false",
		"finally",
		"for",
		"function",
		"if",
		"import",
		"in",
		"instanceof",
		"new",
		"null",
		"return",
		"super",
		"switch",
		"this",
		"throw",
		"true",
		"try",
		"typeof",
		"var",
		"void",
		"while",
		"with"
	];

	// Ordered longest-first so greedy matching works.
	static final PUNCTUATORS:Array<String> = [
		">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "++", "--", "+=", "-=",
		"*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>", "{", "}", "(", ")", "[", "]", ";", ",", "<", ">", "+", "-", "*", "/", "%", "&", "|", "^", "!",
		"~", "?", ":", "=", ".", "@"
	];

	final src:String;
	final tokens:Array<Token> = [];

	/** One entry per open '{'. true means the brace opened a template substitution `${`. */
	final braces:Array<Bool> = [];

	var pos = 0;
	var line = 1;
	var lineStart = 0;
	var sawNewline = false;

	public function new(src:String) {
		this.src = src;
	}

	public function tokenize():Array<Token> {
		if (StringTools.startsWith(src, "#!")) {
			while (pos < src.length && !isNewline(ch(pos)))
				pos++;
		}
		while (true) {
			skipTrivia();
			if (pos >= src.length) {
				tokens.push(new Token(TEOF, "", line, col(), pos, pos, sawNewline));
				break;
			}
			readToken();
			sawNewline = false;
		}
		return tokens;
	}

	inline function ch(i:Int):String {
		return i < src.length ? src.charAt(i) : "";
	}

	inline function col():Int {
		return pos - lineStart + 1;
	}

	static function code(c:String):Int {
		var v = c.charCodeAt(0);
		return v == null ? -1 : v;
	}

	static function isNewline(c:String):Bool {
		return c == "\n" || c == "\r" || c == "\u2028" || c == "\u2029";
	}

	static function isDigit(c:String):Bool {
		var k = code(c);
		return k >= 48 && k <= 57;
	}

	static function isHexDigit(c:String):Bool {
		var k = code(c);
		return (k >= 48 && k <= 57) || (k >= 97 && k <= 102) || (k >= 65 && k <= 70);
	}

	static function isIdStart(c:String):Bool {
		var k = code(c);
		return c != "" && (k == 36 || k == 95 || (k >= 97 && k <= 122) || (k >= 65 && k <= 90) || k > 127);
	}

	static function isIdPart(c:String):Bool {
		return isIdStart(c) || isDigit(c);
	}

	function skipTrivia():Void {
		while (pos < src.length) {
			var c = ch(pos);
			if (isNewline(c)) {
				sawNewline = true;
				pos++;
				if (c == "\r" && ch(pos) == "\n")
					pos++;
				line++;
				lineStart = pos;
			} else if (c == " " || c == "\t" || c == "\u000B" || c == "\u000C" || c == "\u00A0" || c == "\uFEFF") {
				pos++;
			} else if (c == "/" && ch(pos + 1) == "/") {
				while (pos < src.length && !isNewline(ch(pos)))
					pos++;
			} else if (c == "/" && ch(pos + 1) == "*") {
				var end = src.indexOf("*/", pos + 2);
				if (end < 0)
					throw new ParseError("Unterminated comment", line, col());
				var k = pos + 2;
				while (k < end) {
					var cc = ch(k);
					if (cc == "\n" || cc == "\u2028" || cc == "\u2029" || (cc == "\r" && ch(k + 1) != "\n")) {
						sawNewline = true;
						line++;
						lineStart = k + 1;
					}
					k++;
				}
				pos = end + 2;
			} else {
				break;
			}
		}
	}

	function readToken():Void {
		var start = pos;
		var sl = line;
		var sc = col();
		var c = ch(pos);

		if (c == "#" && isIdStart(ch(pos + 1))) {
			pos++;
			var priv = readIdentName();
			emit(TPrivate, priv, start, sl, sc);
			return;
		}
		if (isIdStart(c)) {
			var name = readIdentName();
			emit(KEYWORDS.indexOf(name) >= 0 ? TKeyword : TIdent, name, start, sl, sc);
			return;
		}
		if (isDigit(c) || (c == "." && isDigit(ch(pos + 1)))) {
			readNumber(start, sl, sc);
			return;
		}
		if (c == "\"" || c == "'") {
			readString(c, start, sl, sc);
			return;
		}
		if (c == "`") {
			pos++;
			readTemplate(start, sl, sc, true);
			return;
		}
		if (c == "}" && braces.length > 0 && braces[braces.length - 1]) {
			braces.pop();
			pos++;
			readTemplate(start, sl, sc, false);
			return;
		}
		if (c == "/" && regexAllowed()) {
			readRegExp(start, sl, sc);
			return;
		}
		readPunctuator(start, sl, sc);
	}

	function emit(type:TokenType, value:String, start:Int, sl:Int, sc:Int):Token {
		var t = new Token(type, value, sl, sc, start, pos, sawNewline);
		tokens.push(t);
		return t;
	}

	function readIdentName():String {
		var s = pos;
		while (pos < src.length && isIdPart(ch(pos)))
			pos++;
		return src.substring(s, pos);
	}

	function regexAllowed():Bool {
		if (tokens.length == 0)
			return true;
		var p = tokens[tokens.length - 1];
		return switch p.type {
			case TNumber, TBigInt, TString, TRegExp, TPrivate: false;
			case TTemplate: !p.tail;
			case TIdent: false;
			case TKeyword: !(p.value == "this" || p.value == "super" || p.value == "null" || p.value == "true" || p.value == "false");
			case TPunct: !(p.value == ")" || p.value == "]");
			case TEOF: true;
		};
	}

	function readNumber(start:Int, sl:Int, sc:Int):Void {
		var prefix = ch(pos + 1).toLowerCase();
		var value:Float = 0;
		var text:String;

		if (ch(pos) == "0" && (prefix == "x" || prefix == "o" || prefix == "b")) {
			var base = prefix == "x" ? 16 : (prefix == "o" ? 8 : 2);
			pos += 2;
			var s = pos;
			while (pos < src.length && (isHexDigit(ch(pos)) || ch(pos) == "_"))
				pos++;
			var digits = StringTools.replace(src.substring(s, pos), "_", "");
			for (d in digits.split("")) {
				value = value * base + (Std.parseInt("0x" + d) ?? 0);
			}
			text = src.substring(start, pos);
		} else {
			while (isDigit(ch(pos)) || ch(pos) == "_")
				pos++;
			if (ch(pos) == ".") {
				pos++;
				while (isDigit(ch(pos)) || ch(pos) == "_")
					pos++;
			}
			if (ch(pos) == "e" || ch(pos) == "E") {
				pos++;
				if (ch(pos) == "+" || ch(pos) == "-")
					pos++;
				while (isDigit(ch(pos)))
					pos++;
			}
			text = StringTools.replace(src.substring(start, pos), "_", "");
			value = Std.parseFloat(text);
		}

		if (ch(pos) == "n") {
			pos++;
			emit(TBigInt, text, start, sl, sc);
			return;
		}
		if (isIdStart(ch(pos)))
			throw new ParseError("Identifier starts immediately after a number", sl, sc);

		var t = emit(TNumber, text, start, sl, sc);
		t.numValue = value;
	}

	function readString(quote:String, start:Int, sl:Int, sc:Int):Void {
		pos++; // Skip the opening quote
		var buf = new StringBuf();
		while (true) {
			if (pos >= src.length)
				throw new ParseError("Unterminated string literal", sl, sc);
			var c = ch(pos);
			if (c == quote) {
				pos++;
				break;
			}
			if (c == "\\") {
				buf.add(readEscape());
				continue;
			}
			if (c == "\n" || c == "\r")
				throw new ParseError("Unterminated string literal", sl, sc);
			buf.add(c);
			pos++;
		}
		emit(TString, buf.toString(), start, sl, sc);
	}

	function readEscape():String {
		pos++; // skip that backslash!
		var c = ch(pos);
		pos++;
		switch c {
			case "n":
				return "\n";
			case "t":
				return "\t";
			case "r":
				return "\r";
			case "b":
				return "\u0008";
			case "f":
				return "\u000C";
			case "v":
				return "\u000B";
			case "0":
				return "\u0000";
			case "x":
				var hx = src.substr(pos, 2);
				pos += 2;
				return String.fromCharCode(hex(hx));
			case "u":
				var cp:Int;
				if (ch(pos) == "{") {
					var end = src.indexOf("}", pos);
					cp = hex(src.substring(pos + 1, end));
					pos = end + 1;
				} else {
					cp = hex(src.substr(pos, 4));
					pos += 4;
				}
				return codePointToString(cp);
			case "\r":
				if (ch(pos) == "\n")
					pos++;
				line++;
				lineStart = pos;
				return "";
			case "\n", "\u2028", "\u2029":
				line++;
				lineStart = pos;
				return "";
			default:
				return c;
		}
	}

	static function hex(s:String):Int {
		return Std.parseInt("0x" + s) ?? 0;
	}

	static function codePointToString(cp:Int):String {
		if (cp <= 0xFFFF)
			return String.fromCharCode(cp);
		var v = cp - 0x10000;
		return String.fromCharCode((v >> 10) + 0xD800) + String.fromCharCode((v & 0x3FF) + 0xDC00);
	}

	function readTemplate(start:Int, sl:Int, sc:Int, head:Bool):Void {
		var buf = new StringBuf();
		var rawStart = pos;
		var tail = false;
		while (true) {
			if (pos >= src.length)
				throw new ParseError("Unterminated template literal", sl, sc);
			var c = ch(pos);
			if (c == "`") {
				tail = true;
				break;
			}
			if (c == "$" && ch(pos + 1) == "{")
				break;
			if (c == "\\") {
				buf.add(readEscape());
				continue;
			}
			if (isNewline(c)) {
				buf.add("\n");
				pos++;
				if (c == "\r" && ch(pos) == "\n")
					pos++;
				line++;
				lineStart = pos;
				continue;
			}
			buf.add(c);
			pos++;
		}
		var raw = src.substring(rawStart, pos);
		if (tail) {
			pos++; // skip closing backtick
		} else {
			pos += 2; // skip that ${
			braces.push(true);
		}
		var t = emit(TTemplate, buf.toString(), start, sl, sc);
		t.raw = raw;
		t.head = head;
		t.tail = tail;
	}

	function readRegExp(start:Int, sl:Int, sc:Int):Void {
		pos++; // skeeeep opening slash
		var s = pos;
		var inClass = false;
		while (true) {
			if (pos >= src.length || isNewline(ch(pos)))
				throw new ParseError("Unterminated regular expression", sl, sc);
			var c = ch(pos);
			if (c == "\\") {
				pos += 2;
				continue;
			}
			if (c == "[")
				inClass = true;
			else if (c == "]")
				inClass = false;
			else if (c == "/" && !inClass)
				break;
			pos++;
		}
		var pattern = src.substring(s, pos);
		pos++; // and now that closing slash
		var fs = pos;
		while (isIdPart(ch(pos)))
			pos++;
		var t = emit(TRegExp, pattern, start, sl, sc);
		t.flags = src.substring(fs, pos);
	}

	function readPunctuator(start:Int, sl:Int, sc:Int):Void {
		if (ch(pos) == "?" && ch(pos + 1) == "." && !isDigit(ch(pos + 2))) {
			pos += 2;
			emit(TPunct, "?.", start, sl, sc);
			return;
		}
		for (p in PUNCTUATORS) {
			if (src.substr(pos, p.length) == p) {
				pos += p.length;
				if (p == "{")
					braces.push(false);
				else if (p == "}" && braces.length > 0)
					braces.pop();
				emit(TPunct, p, start, sl, sc);
				return;
			}
		}
		throw new ParseError('Unexpected character "${ch(pos)}"', sl, sc);
	}
}
