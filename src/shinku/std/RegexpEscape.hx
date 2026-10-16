package shinku.std;

import haxe.io.Error;
import haxe.ds.StringMap;

class RegexpEscape {
	static final RESERVED_CHARS:StringMap<String> = createReservedChars();

	static function createReservedChars():StringMap<String> {
		var chars = new StringMap<String>();

		chars.set("&", "\\x26");
		chars.set("!", "\\x21");
		chars.set("#", "\\x23");
		chars.set("$", "\\$");
		chars.set("%", "\\x25");
		chars.set("*", "\\*");
		chars.set("+", "\\+");
		chars.set(",", "\\x2c");
		chars.set(".", "\\.");
		chars.set(":", "\\x3a");
		chars.set(";", "\\x3b");
		chars.set("<", "\\x3c");
		chars.set("=", "\\x3d");
		chars.set(">", "\\x3e");
		chars.set("?", "\\?");
		chars.set("@", "\\x40");
		chars.set("^", "\\^");
		chars.set("`", "\\x60");
		chars.set("~", "\\x7e");
		chars.set("(", "\\(");
		chars.set(")", "\\)");
		chars.set("[", "\\[");
		chars.set("]", "\\]");
		chars.set("{", "\\{");
		chars.set("}", "\\}");
		chars.set("/", "\\/");
		chars.set("-", "\\x2d");
		chars.set("\\", "\\\\");
		chars.set("|", "\\|");

		return chars;
	}

	/**
	 * Escapes arbitrary text for interpolation into a regular expression,
	 * ensuring that the text matches literally.
	 *
	 * @param str The string to escape.
	 * @return The escaped string.
	 */
	public static function escape(str:String):String {
		var result = new StringBuf();

		for (i in 0...str.length) {
			var char = str.charAt(i);

			if (RESERVED_CHARS.exists(char)) {
				result.add(RESERVED_CHARS.get(char));
			} else {
				result.add(char);
			}
		}

		var escaped = result.toString();

		// Escape a leading ASCII letter or digit using hexadecimal notation.
		if (escaped.length > 0) {
			var first = escaped.charAt(0);
			var code = first.charCodeAt(0);

			if (code == null)
				throw Error.Blocked;

			if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
				var hex = StringTools.hex(code, 2).toLowerCase();
				escaped = "\\x" + hex + escaped.substr(1);
			}
		}

		return escaped;
	}
}
