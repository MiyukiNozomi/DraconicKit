package shinku.std.io;

import haxe.io.Error;
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

	public static function runCommand(command:String) {
		final process = new sys.io.Process(command);
		if (process.exitCode() != 0) {
			throw Error.Custom("Couldnt not run command: " + command);
		}
		return process.stdout.readAll().toString();
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

	public static function getProcessorCount():Int {
		var result = "";

		var osName = Sys.systemName();
		Logger.debug("SystemTools.getProcessorCount: OS name: " + osName);

		if (osName == "Windows") {
			var env = Sys.getEnv("NUMBER_OF_PROCESSORS");

			if (env != null) {
				result = env;
			}
		} else if (osName == "Linux" || osName.indexOf("BSD") != -1) {
			result = SystemTools.runCommand("nproc");

			if (result == null && osName == "Linux") {
				var cpuinfo = SystemTools.runCommand("cat /proc/cpuinfo");

				if (cpuinfo != null) {
					var split = cpuinfo.split("processor");
					result = Std.string(split.length - 1);
				}
			}
		} else if (osName == "Mac") {
			var cores = ~/Total Number of Cores: (\d+)/;
			var output = SystemTools.runCommand("/usr/sbin/system_profiler -detailLevel full SPHardwareDataType");

			if (cores.match(output)) {
				result = cores.matched(1);
			}
		}

		var cores = Std.parseInt(result);
		return Std.int(Math.max(cores != null ? cores : 1, 1));
	}

	/***
		# INTERNAL USAGE ONLY!

		This is DraconicKit's home directory, NOT THE USER DIRECTORY! 
	**/
	public static function thisHomeDir() {
		return Path.directory(Path.directory(Sys.programPath()));
	}
}
