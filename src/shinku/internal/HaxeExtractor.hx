package shinku.internal;

import haxe.io.Path;
import sys.io.File;

using Lambda;

typedef ParsedClass = {
	var className:Null<String>;
	var moduleName:String;
	var extendedClass:Null<String>;
}

class HaxeExtractor {
	public static function tokenize(pathname:String):Array<String> {
		return File.getContent(pathname)
			.split("\n")
			.map((line) -> StringTools.trim(line))
			.flatMap((line) -> line.split(" "))
			.filter((token) -> token.length > 0);
	}

	public static function getClasses(pathname:String):Array<String> {
		var tokens = tokenize(pathname);
		var classes:Array<String> = [];

		var i = 0;
		while (i < tokens.length) {
			if (tokens[i++] != "class")
				continue;

			if (i < tokens.length)
				classes.push(tokens[i++]);
		}

		return classes;
	}

	public static function getClassInformation(pathname:String, expectedExtendedClass:String):ParsedClass {
		var tokens = tokenize(pathname);

		var className:Null<String> = null;
		var extendedClass:Null<String> = null;

		var i = 0;
		while (i < tokens.length) {
			if (tokens[i++] != "class")
				continue;

			className = i < tokens.length ? tokens[i++] : null;

			if (className != null && i < tokens.length && tokens[i++] == "extends" && i < tokens.length && tokens[i++] == expectedExtendedClass) {
				extendedClass = expectedExtendedClass;
				break;
			}
		}

		return {
			className: className,
			moduleName: StringTools.replace(Path.withoutDirectory(pathname), ".hx", ""),
			extendedClass: extendedClass
		};
	}
}
