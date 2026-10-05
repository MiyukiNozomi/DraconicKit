package ryuu;

import sys.thread.Thread;

class Logger {
	public static function debug(?p:haxe.PosInfos, ...args:Dynamic) {
		var safeSrc = p != null ? p.className + ':' + p.lineNumber : "<unknown>";
		safeSrc = StringTools.rpad(safeSrc, " ", 27);
		var threadName = Thread.current().name;

		Sys.println("(" + threadName + ") " + '[${safeSrc}] > ' + args.toArray().join(" "));
	}
}
