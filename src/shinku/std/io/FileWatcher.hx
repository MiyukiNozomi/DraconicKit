package shinku.std.io;

import haxe.io.Path;
import sys.FileSystem;

enum FileEvent {
	Added(path:String);
	Modified(path:String);
	Removed(path:String);
}

private typedef Stamp = {mtime:Float, size:Int};

class FileWatcher {
	public var intervalMs(default, null):Int;

	final root:String;
	final onEvent:FileEvent->Void;
	final ignore:String->Bool;
	var snapshot:Map<String, Stamp>;
	var running = false;

	public function new(root:String, onEvent:FileEvent->Void, intervalMs:Int = 500, ?ignore:String->Bool) {
		this.root = root;
		this.onEvent = onEvent;
		this.intervalMs = intervalMs;
		this.ignore = ignore != null ? ignore : (_ -> false);
		snapshot = new Map();
		snapshot = scan(root, new Map());
	}

	function scan(dir:String, into:Map<String, Stamp>):Map<String, Stamp> {
		var entries = try FileSystem.readDirectory(dir) catch (_:Dynamic) return into;
		for (name in entries) {
			var path = Path.join([dir, name]);
			if (ignore(path))
				continue;
			try {
				var st = FileSystem.stat(path);
				if (FileSystem.isDirectory(path))
					scan(path, into);
				else
					into[path] = {mtime: st.mtime.getTime(), size: st.size};
			} catch (_:Dynamic) {}
		}
		return into;
	}

	public function tick():Void {
		var next = scan(root, new Map());
		for (path => stamp in next) {
			var old = snapshot[path];
			if (old == null)
				onEvent(Added(path));
			else if (old.mtime != stamp.mtime || old.size != stamp.size)
				onEvent(Modified(path));
		}
		for (path in snapshot.keys())
			if (!next.exists(path))
				onEvent(Removed(path));
		snapshot = next;
	}

	public function run():Void {
		running = true;
		while (running) {
			Sys.sleep(intervalMs / 1000);
			tick();
		}
	}

	public function stop():Void
		running = false;
}
