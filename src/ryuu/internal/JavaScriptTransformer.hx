package ryuu.internal;

import haxe.io.Error;
import haxe.io.Path;
import haxe.Json;

class JavaScriptTransformer {
	private static function tokenize(input:String):Array<String> {
		var chars = input.split('');
		var tokens = new Array<String>();

		final isLetter = (s:String) -> {
			var ch = s.charCodeAt(0);
			return ch != null && (('A'.code <= ch && ch <= 'Z'.code) || ('a'.code <= ch && ch <= 'z'.code));
		};

		var i = 0;

		while (i < chars.length) {
			var ch = chars[i];

			if (isLetter(ch)) {
				var token = "";

				while (i < chars.length && isLetter(chars[i])) {
					token += chars[i];
					i++;
				}

				tokens.push(token);
			} else if (ch == '"' || ch == "'") {
				var quote = ch;
				var token = quote;
				i++;

				while (i < chars.length) {
					ch = chars[i];

					if (ch == '\\' && i + 1 < chars.length) {
						token += chars[i];
						token += chars[i + 1];
						i += 2;
						continue;
					}

					token += ch;
					i++;

					if (ch == quote)
						break;
				}

				tokens.push(token);
			} else {
				tokens.push(ch);
				i++;
			}
		}

		return tokens;
	}

	public static function transform(input:String) {
		#if dev
		#else
		return input;
		#end

		final transformPathname = (pathname:String) -> {
			if (!StringTools.startsWith(pathname, pathname.charAt(0) + '.')) {
				//		trace("Found a import statement towards " + pathname);
				var dst = (Json.stringify(Path.join(["/@module", pathname.substring(1, pathname.length - 1)])));
				return dst;
			} else {
				return (pathname);
			}
		}

		var tokens = tokenize(input);

		var transformedTokens = new Array<String>();

		var i = 0;
		while (i < tokens.length) {
			if (tokens[i] == "from") {
				transformedTokens.push(tokens[i++]);
				while (i < tokens.length && (tokens[i].length == 0 || StringTools.trim(tokens[i]).length == 0)) {
					transformedTokens.push(tokens[i++]);
				}
				var pathname = tokens[i++];

				if (pathname != null && (pathname.charAt(0) == "'" || pathname.charAt(0) == "\"")) {
					transformedTokens.push(transformPathname(pathname));
				}
				continue;
			} else if (tokens[i] == "import") {
				var replacePos = transformedTokens.length;
				transformedTokens.push(tokens[i++]);
				while (i < tokens.length && (tokens[i].length == 0 || StringTools.trim(tokens[i]).length == 0)) {
					transformedTokens.push(tokens[i++]);
				}

				if (i < tokens.length)
					if (tokens[i] == '(') {
						transformedTokens[replacePos] = "window.draconicImport";
					} else if (tokens[i].charAt(0) == "'" || tokens[i].charAt(0) == "\"") {
						transformedTokens.push(transformPathname(tokens[i++]));
					}
				continue;
			}

			transformedTokens.push(tokens[i++]);
		}

		return '
// inserted by DraconicKit.
if (!window.draconicImport) {
    window.draconicImport = (path) => {
        if (!path || typeof path !== "string") {
            throw new Error("Bad import path: " + path);
        } 
        return import(path.startsWith(".") ? path : `/@module/`+path)
    }    
}   
    '
			+ transformedTokens.join('');
	}
}
