package testing;

import org.mozilla.javascript.annotations.JSFunction;
import haxe.ds.StringMap;

class Checker {
	private var pendingList:Array<String> = [];
	private var results:StringMap<Bool> = new StringMap<Bool>();
	private var resultOrder:Array<String> = [];

	public function new() {}

	@:strict(JSFunction)
	public function pending(name:String):Void {
		if (pendingList.indexOf(name) == -1) {
			pendingList.push(name);
		}
	}

	@:strict(JSFunction)
	public function check(name:String, ok:Bool):Void {
		pendingList.remove(name);

		if (!results.exists(name)) {
			resultOrder.push(name);
		}

		results.set(name, ok);

		trace((ok ? "PASS  " : "FAIL  ") + name);
	}

	@:strict(JSFunction)
	public function note(name:String, info:String):Void {
		trace("INFO  " + name + ": " + info);
	}

	@:strict(JSFunction)
	public function report():Void {
		for (name in pendingList) {
			trace("FAIL  " + name + " (never completed; job queue not drained or test threw?)");
		}

		var passed:Int = 0;
		var failed:Int = 0;

		for (name in resultOrder) {
			if (results.get(name) == true) {
				passed++;
			} else {
				failed++;
			}
		}

		trace("\n" + passed + " passed, " + failed + " failed, " + pendingList.length + " never completed");
	}
}
