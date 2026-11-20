package shinku.scheduling;

import shinku.std.io.SystemTools;
import shinku.Console.Logger;
import haxe.io.Error;
import shinku.scheduling.ThreadPool;

/**
	A Class that manage server-wide threads.

	Mostly used to delegate the job of http connections and websockets.
**/
class Executor {
	private static var pool:Null<ElasticThreadPool>;

	public static function prepare() {
		var n = SystemTools.getProcessorCount();
		pool = new ElasticThreadPool(n);
		Logger.debug("Working with a maximum of " + n + " worker threads.");
	}

	public static function schedule(task:() -> Void) {
		if (pool == null)
			throw Error.Blocked;
		pool.run(() -> {
			task();
		});
	}
}
