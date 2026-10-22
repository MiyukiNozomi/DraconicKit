package shinku.internal;

import shinku.Console.Logger;
import sys.FileSystem;
import shinku.internal.esm.ESMResolver;
import haxe.io.Path;
import haxe.Json;

using StringTools;

private enum TokenKind {
	Ident;
	Str;
	Trivia; // whitespace + comments
	Punct;
	Other; // numbers, template literals, regex literals
}

private typedef Token = {
	var kind:TokenKind;
	var text:String;
}

class JavaScriptTransformer {
	// Defined per module on purpose: a relative import() resolves against the
	// module that *contains the call*, so a single shared helper would resolve
	// every relative dynamic import against whichever module defined it first.
	// Kept on one line (no trailing newline) so line numbers don't shift.
	static final PREAMBLE = "/* inserted by DraconicKit. */ const __draconicImport = (p, o) => { "
		+ "if (!p || (typeof p !== 'string' && !(p instanceof URL))) throw new Error('Bad import path: ' + p); "
		+ "const s = String(p); "
		+ "return import(/^(\\.{1,2}(\\/|$)|\\/|[a-zA-Z][a-zA-Z\\d+.-]*:)/.test(s) ? s : '/@module/' + s, o); "
		+ "}; ";

	static final REGEX_AFTER_KEYWORD = [
		"return",
		"typeof",
		"instanceof",
		"in",
		"of",
		"new",
		"delete",
		"void",
		"throw",
		"case",
		"do",
		"else",
		"yield",
		"await"
	];

	static final URL_LIKE = ~/^(https?|data|blob):/i;

	// ---------------------------------------------------------------- lexing

	private static inline function isSpace(c:Int):Bool
		return c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12;

	private static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	private static inline function isIdentStart(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == "$".code || c > 127;

	private static inline function isIdentPart(c:Int):Bool
		return isIdentStart(c) || isDigit(c);

	private static function skipLineComment(s:String, start:Int):Int {
		var i = start;
		while (i < s.length && s.fastCodeAt(i) != 10 && s.fastCodeAt(i) != 13)
			i++;
		return i;
	}

	private static function skipBlockComment(s:String, start:Int):Int {
		var end = s.indexOf("*/", start + 2);
		return end == -1 ? s.length : end + 2;
	}

	private static function skipString(s:String, start:Int):Int {
		var quote = s.fastCodeAt(start);
		var i = start + 1;
		while (i < s.length) {
			var c = s.fastCodeAt(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == quote)
				return i + 1;
			if (c == 10) // unterminated, don't swallow the rest of the file
				return i;
			i++;
		}
		return s.length;
	}

	private static function skipTemplate(s:String, start:Int):Int {
		var i = start + 1;
		while (i < s.length) {
			var c = s.fastCodeAt(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == "`".code)
				return i + 1;
			if (c == "$".code && s.charCodeAt(i + 1) == "{".code) {
				i = skipBraces(s, i + 2);
				continue;
			}
			i++;
		}
		return s.length;
	}

	// `start` is just after "${"; returns the index after the matching "}"
	private static function skipBraces(s:String, start:Int):Int {
		var depth = 1;
		var i = start;
		while (i < s.length) {
			var c = s.fastCodeAt(i);
			if (c == "'".code || c == '"'.code) {
				i = skipString(s, i);
				continue;
			}
			if (c == "`".code) {
				i = skipTemplate(s, i);
				continue;
			}
			if (c == "/".code) {
				var n = s.charCodeAt(i + 1);
				if (n == "/".code) {
					i = skipLineComment(s, i);
					continue;
				}
				if (n == "*".code) {
					i = skipBlockComment(s, i);
					continue;
				}
			}
			if (c == "{".code) {
				depth++;
			} else if (c == "}".code) {
				depth--;
				if (depth == 0)
					return i + 1;
			}
			i++;
		}
		return s.length;
	}

	// returns -1 if this doesn't look like a regex literal
	private static function skipRegex(s:String, start:Int):Int {
		var i = start + 1;
		var inClass = false;
		while (i < s.length) {
			var c = s.fastCodeAt(i);
			if (c == 10 || c == 13)
				return -1;
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (inClass) {
				if (c == "]".code)
					inClass = false;
			} else if (c == "[".code) {
				inClass = true;
			} else if (c == "/".code) {
				i++;
				while (i < s.length && isIdentPart(s.fastCodeAt(i)))
					i++; // flags
				return i;
			}
			i++;
		}
		return -1;
	}

	// is a "/" at this point a regex start (true) or a division (false)?
	private static function regexAllowed(prev:Token):Bool {
		if (prev == null)
			return true;
		return switch (prev.kind) {
			case Ident: REGEX_AFTER_KEYWORD.contains(prev.text);
			case Punct: prev.text != ")" && prev.text != "]";
			default: false;
		}
	}

	private static function tokenize(s:String):Array<Token> {
		var tokens:Array<Token> = [];
		var prev:Null<Token> = null; // last non-trivia token
		var i = 0;

		function add(kind:TokenKind, end:Int):Void {
			var t:Token = {kind: kind, text: s.substring(i, end)};
			tokens.push(t);
			if (kind != Trivia)
				prev = t;
			i = end;
		}

		while (i < s.length) {
			var c = s.fastCodeAt(i);
			var next = s.charCodeAt(i + 1);

			if (isSpace(c)) {
				var e = i + 1;
				while (e < s.length && isSpace(s.fastCodeAt(e)))
					e++;
				add(Trivia, e);
			} else if (c == "/".code && next == "/".code) {
				add(Trivia, skipLineComment(s, i));
			} else if (c == "/".code && next == "*".code) {
				add(Trivia, skipBlockComment(s, i));
			} else if (c == "'".code || c == '"'.code) {
				add(Str, skipString(s, i));
			} else if (c == "`".code) {
				add(Other, skipTemplate(s, i));
			} else if (isIdentStart(c)) {
				var e = i + 1;
				while (e < s.length && isIdentPart(s.fastCodeAt(e)))
					e++;
				add(Ident, e);
			} else if (isDigit(c)) {
				var e = i + 1;
				while (e < s.length && isIdentPart(s.fastCodeAt(e)))
					e++;
				add(Other, e);
			} else if (c == "/".code && prev != null && regexAllowed(prev)) {
				var e = skipRegex(s, i);
				if (e == -1)
					add(Punct, i + 1);
				else
					add(Other, e);
			} else {
				add(Punct, i + 1);
			}
		}

		return tokens;
	}

	// -------------------------------------------------------------- rewriting

	private static function resolveImport(pathname:String, thisPath:String):String {
		try {
			return ESMResolver.esmResolve(pathname, FileSystem.absolutePath(thisPath));
		} catch (err) {
			Logger.error("Could not resolve " + pathname + " because: ", err, err.stack);
			// fall back to the bare specifier; the /@module/ handler can try to resolve it
			return pathname;
		}
	}

	private static function isPassthrough(spec:String):Bool {
		return spec == "." || spec == ".." || spec.startsWith("./") || spec.startsWith("../") || spec.startsWith("/") || URL_LIKE.match(spec);
	}

	private static function rewriteSpecifier(t:Token, thisPath:String):Void {
		var quote = t.text.charAt(0);
		if (t.text.length < 2 || !t.text.endsWith(quote))
			return;

		var spec = t.text.substring(1, t.text.length - 1);
		if (isPassthrough(spec))
			return;

		t.text = Json.stringify(Path.join(["/@module", resolveImport(spec, thisPath)]));
	}

	private static function nextSignificant(tokens:Array<Token>, start:Int):Int {
		for (i in start...tokens.length) {
			if (tokens[i].kind != Trivia)
				return i;
		}
		return -1;
	}

	public static function transform(input:String, thisPath:String):String {
		var tokens = tokenize(input);
		var out = new StringBuf();
		var prev:Null<Token> = null;

		for (i in 0...tokens.length) {
			var t = tokens[i];

			// `foo.import(...)` / `Array.from(...)` are member accesses, not syntax
			if (t.kind == Ident && (prev == null || prev.text != ".")) {
				switch (t.text) {
					case "import":
						var n = nextSignificant(tokens, i + 1);
						if (n != -1) {
							if (tokens[n].kind == Punct && tokens[n].text == "(") {
								t.text = "__draconicImport";
							} else if (tokens[n].kind == Str) {
								rewriteSpecifier(tokens[n], thisPath); // import "x";
							}
						}
					case "from":
						var n = nextSignificant(tokens, i + 1);
						if (n != -1 && tokens[n].kind == Str) {
							rewriteSpecifier(tokens[n], thisPath); // import/export ... from "x"
						}
					default:
				}
			}

			out.add(t.text);
			if (t.kind != Trivia)
				prev = t;
		}

		return PREAMBLE + out.toString();
	}
}
