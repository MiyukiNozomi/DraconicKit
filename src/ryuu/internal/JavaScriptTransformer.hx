package ryuu.internal;

import haxe.io.Path;
import haxe.Json;

class JavaScriptTransformer {
	private static function tokenize(input:String):Array<String> {
		var chars = input.split('');
		var tokens = new Array<String>();

		final isLetter = (s:String) -> {
			var ch = s.charCodeAt(0);
			if (ch != null)
				return ('A'.code <= ch && ch <= 'Z'.code) || ('a'.code <= ch && ch <= 'z'.code);
			return false;
		};

		var i = 0;
		while (i < chars.length) {
			var ch = chars[i];

			if (isLetter(ch)) {
				var letter = "";

				while (i < chars.length && isLetter(chars[i])) {
					letter += chars[i];
					i++;
				}

				tokens.push(letter);
			} else if (ch == '\""' || ch == '\'') {
				var escapeChar = ch;
				var letter = ch;
				i++;

				while (i < chars.length && chars[i] != escapeChar) {
					if (chars[i] == '\\')
						letter += chars[i++];
					letter += chars[i];
					i++;
				}
				// skip last escapeChar
				letter += escapeChar;
				i++;

				tokens.push(letter);
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

		var tokens = tokenize(input);
		var transformedTokens = new Array();

		var i = 0;
		while (i < tokens.length) {
			if (tokens[i] == "from") {
				while (i < tokens.length && tokens[i].charAt(0) != '\'' && tokens[i].charAt(0) != '\"') {
					transformedTokens.push(tokens[i++]);
				}
				var pathname = tokens[i++];

				if (pathname != null && !StringTools.startsWith(pathname, pathname.charAt(0) + '.')) {
					trace("Found a import statement towards " + pathname);
					transformedTokens.push(Json.stringify(Path.join(["/@module", pathname.substring(1, pathname.length - 1)])));
				} else {
					transformedTokens.push(pathname);
				}
				continue;
			} else if (tokens[i] == "import") {
				var replacePos = transformedTokens.length;
				transformedTokens.push(tokens[i++]);
				while (i < tokens.length && tokens[i].length == 0) {
					transformedTokens.push(tokens[i++]);
				}

				if (tokens[i] == '(') {
					transformedTokens[replacePos] = "window.draconicImport";
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
