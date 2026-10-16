package shinku;

import haxe.PosInfos;
import sys.thread.Mutex;
import sys.thread.Thread;

private typedef LevelStyle = {
	label:String,
	badge:String,
	text:String,
	stderr:Bool
}

class Logger {
	static inline var RESET = "\x1B[0m";
	static inline var DIM = "\x1B[2m";

	static final DEBUG:LevelStyle = {
		label: "DEBUG",
		badge: "\x1B[1;95m",
		text: "\x1B[0;97m",
		stderr: false
	};
	static final INFO:LevelStyle = {
		label: "INFO ",
		badge: "\x1B[1;94m",
		text: "\x1B[0;97m",
		stderr: false
	};
	static final WARN:LevelStyle = {
		label: "WARN ",
		badge: "\x1B[1;93m",
		text: "\x1B[0;33m",
		stderr: true
	};
	static final ERROR:LevelStyle = {
		label: "ERROR",
		badge: "\x1B[1;91m",
		text: "\x1B[0;31m",
		stderr: true
	};

	static final lock = new Mutex();

	public static function info(?p:PosInfos, ...args:Dynamic)
		write(INFO, p, ...args);

	public static function warn(?p:PosInfos, ...args:Dynamic)
		write(WARN, p, ...args);

	public static function error(?p:PosInfos, ...args:Dynamic)
		write(ERROR, p, ...args);

	public static function debug(?p:PosInfos, ...args:Dynamic) {
		if (!Configuration.SHOW_DEBUG_LOGS)
			return;
		write(DEBUG, p, ...args);
	}

	static function write(style:LevelStyle, p:Null<PosInfos>, ...args:Dynamic) {
		var src = p != null ? '${p.className}:${p.lineNumber}' : "<unknown>";
		var thread = Thread.current().name;
		var msg = args.toArray().map(stringify).join(" ");
		var time = Configuration.SHOW_TIMESTAMP_LOGS ? DateTools.format(Date.now(), "%H:%M:%S") + " " : "";

		var line = (Sys.getEnv("NO_COLOR") == null && Configuration.USE_COLORS_IN_LOGS) ? '${DIM}${time}${RESET}${style.badge}${style.label} (${thread}) [${src}] > ${style.text}${msg}${RESET}' : '${time}${style.label} (${thread}) [${src}] > ${msg}';

		lock.acquire();
		try {
			var out = style.stderr ? Sys.stderr() : Sys.stdout();
			out.writeString(line + "\n");
			out.flush();
		} catch (_) {}
		lock.release();
	}

	static function stringify(v:Dynamic):String {
		if (Std.isOfType(v, haxe.Exception)) {
			var e:haxe.Exception = v;
			return e.details();
		}
		return Std.string(v);
	}
}
