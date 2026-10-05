package ryuu.scheduling;

import ryuu.Console.Logger;
import haxe.io.Error;
import ryuu.scheduling.ThreadPool;

// TODO: implement setTimeout?
class Executor {
	private var workers:ThreadPool;

	public function new() {
		var n = Executor.getProcessorCores();
		this.workers = new ThreadPool(n);
		Logger.debug("Working with " + this.workers.threadsCount + " worker threads.");
	}

	public function schedule(task:() -> Void) {
		workers.run(() -> {
			task();
		});
	}

	private static function runCommand(command:String) {
		final process = new sys.io.Process(command);
		if (process.exitCode() != 0) {
			throw Error.Custom("Couldnt not run command: " + command);
		}
		return process.stdout.readAll().toString();
	}

	public static function getProcessorCores():Int {
		var result = "";

		var osName = Sys.systemName();
		Logger.debug("getProcessorCores: OS name: " + osName);

		if (osName == "Windows") {
			var env = Sys.getEnv("NUMBER_OF_PROCESSORS");

			if (env != null) {
				result = env;
			}
		} else if (osName == "Linux" || osName.indexOf("BSD") != -1) {
			result = runCommand("nproc");

			if (result == null && osName == "Linux") {
				var cpuinfo = runCommand("cat /proc/cpuinfo");

				if (cpuinfo != null) {
					var split = cpuinfo.split("processor");
					result = Std.string(split.length - 1);
				}
			}
		} else if (osName == "Mac") {
			var cores = ~/Total Number of Cores: (\d+)/;
			var output = runCommand("/usr/sbin/system_profiler -detailLevel full SPHardwareDataType");

			if (cores.match(output)) {
				result = cores.matched(1);
			}
		}

		var cores = Std.parseInt(result);
		return Std.int(Math.max(cores != null ? cores : 1, 1));
	}
}
