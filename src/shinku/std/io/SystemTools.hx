package shinku.std.io;

import haxe.Json;
import sys.io.File;
import shinku.Console.Logger;
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
		One small note: this does not replace the destination directory if it already exists,
		if the destination directory exists, this function will merge the files, overwriting the existing files on the destination, but
		any extra files will be left alone.
	**/
	public static function recursiveCopy(from:String, destination:String) {
		var absoluteFrom = FileSystem.absolutePath(Path.normalize(from));
		var absoluteDest = FileSystem.absolutePath(Path.normalize(destination));
		visitDirRecursive(from, (fp) -> {
			var replacePath = Path.join([absoluteDest, fp.substring(absoluteFrom.length)]);
			Logger.debug(fp, "->", replacePath);

			FileSystem.createDirectory(Path.directory(replacePath));
			File.copy(fp, replacePath);
		});
	}

	public static function deleteRecursive(path:String) {
		if (!FileSystem.exists(path))
			return;

		if (FileSystem.isDirectory(path)) {
			final entries = FileSystem.readDirectory(path);
			for (entry in entries) {
				deleteRecursive(Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	public static function getSystemUsername() {
		var envs = Sys.environment();
		if (envs.exists("USERNAME")) {
			return envs["USERNAME"];
		}
		if (envs.exists("USER")) {
			return envs["USER"];
		}
		return null;
	}

	/***
		# WARNING
		Do not put unsanitized user input here! this runs shell commands as they are!
		If you are looking to run a shell command from mutable user inputs, properly clean them up first!
	**/
	public static function runShellCommandAt(args:Array<String>, workdir:String) {
		var shellCommand = "cd " + workdir + " && " + args[0] + " " + args.slice(1).map(v -> Json.stringify(v)).join(' ');
		Logger.debug("Running: ", shellCommand);

		#if jvm
		var builder = new java.lang.ProcessBuilder(java.util.Arrays.asList("sh", "-c", shellCommand));
		builder.directory(new java.io.File(workdir));
		builder.inheritIO();

		var process = builder.start();

		return process.waitFor();
		#else
		var process = new sys.io.Process("sh", ["-c", shellCommand], true);
		var ec = process.exitCode();
		process.close();
		return ec;
		#end
	}

	/***
		# INTERNAL USAGE ONLY!

		This is DraconicKit's home directory, NOT THE USER DIRECTORY! 
	**/
	public static function thisHomeDir() {
		return Path.directory(Path.directory(Sys.programPath()));
	}
}
