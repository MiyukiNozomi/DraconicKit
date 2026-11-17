package esper.execution;

#if draconicbuilder
import sys.thread.Mutex;
import shinku.std.io.SystemTools;
import shinku.Console.Logger;
import sys.FileSystem;
import haxe.io.Path;
import haxe.Json;
import haxe.io.Bytes;
import sys.io.Process;

#if windows
#error "Windows is not supported by DraconicKit in development mode."
#end
class NodeRunner {
	private static var PATH_TO_NODEJS = "<You forgot to call NodeRunner.prepare()>";

	private static var lock = new Mutex();

	private static var daemonProcess:Null<Process>;

	public static function prepare() {
		try {
			PATH_TO_NODEJS = StringTools.trim(runCommandAndGetOutput(["which", "node"]));
			Logger.debug("Node.JS path: " + NodeRunner.PATH_TO_NODEJS);

			var daemonPath = Path.join([SystemTools.thisHomeDir(), "packages/node-interop/daemon.js"]);
			daemonProcess = new Process(PATH_TO_NODEJS, [daemonPath], false);
		} catch (e:Dynamic) {
			Logger.error(e);
			throw "Node.JS is not installed or is not on PATH!";
		}
	}

	public static function invoke(method:String, ?params:Dynamic):Dynamic {
		lock.acquire();

		var result:Dynamic = null;
		var failed = false;
		var error:Dynamic = null;

		try {
			result = sendRequest(method, params);
		} catch (e:Dynamic) {
			failed = true;
			error = e;
		}

		lock.release();

		if (failed)
			throw error;
		return result;
	}

	private static function sendRequest(method:String, params:Dynamic):Dynamic {
		if (daemonProcess == null) {
			throw "NodeRunner is not ready!";
		}

		var json = Json.stringify({method: method, params: params});
		var payloadLength = Bytes.ofString(json).length;

		var stdin = daemonProcess.stdin;
		stdin.writeString(payloadLength + " " + json);
		stdin.flush();

		Logger.debug("Sending to node daemon: ", "'" + payloadLength + " " + json + "'");

		var stdout = daemonProcess.stdout;

		var lengthText = stdout.readUntil(0x20);
		var length = Std.parseInt(lengthText);
		if (length == null) {
			throw "Malformed response length from daemon: " + lengthText;
		}

		var body = Bytes.alloc(length);
		stdout.readFullBytes(body, 0, length);
		stdout.readByte();

		var reply:Dynamic = Json.parse(body.toString());
		if (reply.ok != true) {
			throw Std.string(reply.error);
		}
		return reply.response;
	}

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
}
#end
