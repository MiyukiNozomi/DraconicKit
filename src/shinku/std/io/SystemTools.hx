package shinku.std.io;

import haxe.io.Path;
import sys.FileSystem;

class SystemTools {
	private static function visitDirImpl(path:String, visit:(fullPath:String) -> Void) {
		if (FileSystem.isDirectory(path)) {
			final entries = FileSystem.readDirectory(path);
			for (entry in entries) {
				visitDirImpl(Path.join([path, entry]), visit);
			}
		} else {
			visit(path);
		}
	}

	public static function visitDirRecursive(directory:String, visit:(fullPath:String) -> Void) {
		var absolute = FileSystem.absolutePath(Path.normalize(directory));
		visitDirImpl(absolute, visit);
	}

	/***
		# INTERNAL USAGE ONLY!
	**/
	public static function thisHomeDir() {
		return Path.directory(Path.directory(Sys.programPath()));
	}
}
