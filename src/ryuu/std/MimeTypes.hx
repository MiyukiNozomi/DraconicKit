package ryuu.std;

import haxe.macro.Context;
import sys.io.File;
import haxe.io.Path;

class MimeTypes {
	/**
		Just a heads up, this function will return application/octet-stream for unknown extensions.
	 */
	public static function forFilename(filename:String) {
		var ext = Path.extension(filename);
		return fromExtension(ext);
	}

	/**
		Just a heads up, this function will return application/octet-stream for unknown extensions.
	 */
	public static function fromExtension(ext:String):String {
		ext = ext.toLowerCase();
		generate_extension_to_mime();
	}

	// for the non-haxe nerds
	// this is kind of like a mixin
	// i basically generate a big ass switch statement containing extension -> mime type.
	// better than hand writing it :)
	private static macro function generate_extension_to_mime() {
		// if for some reason that file turned into dust
		// or the IRS taxed it
		// take it from Apache's HTTPD.
		// And please dont change the encoding of that file!
		var decoderFile = File.read("src/external/mime.types")
			.readAll()
			.toString()
			.split("\n")
			.filter(v -> !StringTools.startsWith(v, '#'));

		var cases = new Array<String>();

		var alreadyAddedCases = new Array<String>();

		for (line in decoderFile) {
			var separator = line.indexOf('\t');
			if (separator == -1)
				continue;
			var mimeType = StringTools.trim(line.substring(0, separator));
			var extensions = StringTools.trim(line.substring(separator))
				.split(' ')
				.map(v -> '"${StringTools.trim(v)}"')
				.filter(v -> v.length > 2)
				.filter(v -> {
					if (alreadyAddedCases.contains(v))
						return false;
					alreadyAddedCases.push(v);
					return true;
				});

			if (extensions.length == 0)
				continue;

			cases.push('\tcase ${extensions.join(", ")}: "${mimeType}";');
		}

		var code = "return switch(ext) {\n" + cases.join("\n") + '\n\tdefault: "application/octet-stream";\n}';

		// trace("List of supported Extension -> mimeType : ", alreadyAddedCases);

		return Context.parse(code, Context.currentPos());
	}
}
