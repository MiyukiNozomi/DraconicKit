package shinku.internal.esm;

import shinku.std.io.SystemTools;
import shinku.Console.Logger;
import sys.FileSystem;
import haxe.io.Path;
import haxe.Json;
import haxe.io.Bytes;
import sys.io.Process;

#if dev
#if windows
#error "Windows is not supported by DraconicKit in development mode."
#end
class NodeRunner {
	private static var PATH_TO_NODEJS = "<You forgot to call NodeRunner.ensureNodeJSIsInstalled()>";

	private static function runCommandAndGetOutput(command:Array<String>, ?inputData:Null<Bytes>):String {
		var output = new Process(command[0], command.slice(1), false);
		if (inputData != null) {
			try {
				output.stdin.write(inputData);
				output.stdin.flush();
				output.stdin.close();
			} catch (e) {
				var exitCode = output.exitCode(false);
				if (exitCode != null) {
					var stdoutStr = output.stdout.readAll().toString();
					var stderrStr = output.stderr.readAll().toString();
					Logger.error("FATAL: runCommandAndGetOutput couldnt even write to the stdin! exit code: "
						+ exitCode
						+ " with message: "
						+ stdoutStr
						+ stderrStr);
				}
				throw e;
			}
		}

		var exitCode = output.exitCode(true);
		var stdoutStr = output.stdout.readAll().toString();

		if (exitCode != 0) {
			var stderrStr = output.stderr.readAll().toString();
			output.close();
			throw "Non-Zero exit code "
				+ exitCode
				+ " when running command: "
				+ Json.stringify(command)
				+ "\n"
				+ stdoutStr
				+ "\n"
				+ stderrStr;
		}
		output.close();

		return stdoutStr;
	}

	public static function ensureNodeJSIsInstalled() {
		try {
			NodeRunner.PATH_TO_NODEJS = StringTools.trim(runCommandAndGetOutput(["which", "node"]));
			Logger.debug("Node.JS path: " + NodeRunner.PATH_TO_NODEJS);
		} catch (e:Dynamic) {
			Logger.error(e);
			throw "Node.JS is not installed or is not on PATH!";
		}
	}

	public static function runNodeScript<T>(name:String, input:Dynamic):T {
		var pathname = FileSystem.absolutePath(Path.join([SystemTools.thisHomeDir(), "scripts", name]));
		if (!FileSystem.exists(pathname)) {
			throw "Attempted to run a NodeJS script that does not exist: " + pathname;
		}
		if (!FileSystem.exists(PATH_TO_NODEJS)) {
			throw "Attempted to run a NodeJS script with.. a non-existant NodeJS installation: " + PATH_TO_NODEJS;
		}
		return Json.parse(runCommandAndGetOutput([PATH_TO_NODEJS, pathname], Bytes.ofString(Json.stringify(input))));
	}
}
#end
