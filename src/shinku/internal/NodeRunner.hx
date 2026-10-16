package shinku.internal;

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
	private static var PATH_TO_NODEJS = "false";

	private static function runCommandAndGetOutput(command:Array<String>, ?inputData:Null<Bytes>):String {
		var output = new Process(command[0], command.slice(1), false);
		if (inputData != null) {
			output.stdin.write(inputData);
			output.stdin.flush();
			output.stdin.close();
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
		var pathname = FileSystem.absolutePath(Path.join([Path.directory(Path.directory(Sys.programPath())), "scripts", name]));
		if (!FileSystem.exists(pathname)) {
			throw "Attempted to run a NodeJS script that does not exist: " + pathname;
		}
		return Json.parse(runCommandAndGetOutput([PATH_TO_NODEJS, pathname], Bytes.ofString(Json.stringify(input))));
	}
}
#end
