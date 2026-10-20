package shinku.internal;

import shinku.Console.AnsiPrinter;

class StdinPrompt {
	static inline var RESET = "§0m";
	static inline var ACCENT = "§96m";
	static inline var TEXT = "§0;97m";
	static inline var USER_VALUE = "§0;37m";
	static inline var DIM = "§90m";
	static inline var ERROR = "§91m";

	public static function confirm(question:String, defaultYes:Bool = true) {
		var hint = defaultYes ? "[Y/n]" : "[y/N]";
		while (true) {
			AnsiPrinter.print('${ACCENT}\u276F ${TEXT}$question ${DIM}$hint ${RESET}');
			var line = readLine();
			if (line == null)
				return defaultYes;
			switch (line.toLowerCase()) {
				case "":
					return defaultYes;
				case "y" | "yes":
					return true;
				case "n" | "no":
					return false;
				default:
					AnsiPrinter.print('${ERROR}\u25A0 Please answer y or n.${RESET}\n');
			}
		}
	}

	public static function ask(question:String, ?defaultValue:String):String {
		var def = defaultValue != null ? '${DIM} ($defaultValue)' : "";
		while (true) {
			AnsiPrinter.print('${ACCENT}\u25C6 ${TEXT}$question$def${RESET}:${USER_VALUE} ');
			var line = readLine();
			if (line == null)
				return defaultValue != null ? defaultValue : "";
			if (line != "")
				return line;
			if (defaultValue != null)
				return defaultValue;
			AnsiPrinter.print('${ERROR}\u25A0 This can\'t be empty.${RESET}\n');
		}
	}

	public static function choose(question:String, options:Array<String>) {
		AnsiPrinter.print('${ACCENT}\u25C6 ${TEXT}$question${RESET}\n');
		for (i in 0...options.length)
			AnsiPrinter.print('  ${ACCENT}${i + 1})${RESET} ${options[i]}\n');

		while (true) {
			AnsiPrinter.print('${DIM}Choice [1-${options.length}]: ${RESET}');
			var line = readLine();
			if (line == null)
				return options[0];
			var n = Std.parseInt(line);
			if (n != null && n >= 1 && n <= options.length)
				return options[n - 1];
			AnsiPrinter.print('${ERROR}\u25A0 Invalid choice, try again.${RESET}\n');
		}
	}

	static function readLine():Null<String> {
		try {
			return StringTools.trim(Sys.stdin().readLine());
		} catch (e:haxe.io.Eof) {
			return null;
		}
	}
}
