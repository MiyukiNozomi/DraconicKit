package shinku;

import haxe.io.Error;
import haxe.io.Output;
import haxe.PosInfos;
import sys.thread.Mutex;
import sys.thread.Thread;

class AnsiPrinter {
	/**
		This function removes all §-prefixed colors.
	**/
	public static function removeColors(text:String) {
		final COLOR_CODE = ~/§[0-9;]*m/g;
		return COLOR_CODE.replace(text, "");
	}

	/**
		So, this function basically changes the prefix from \e[ to just §	
		these are ANSI, and *nix only (foreground only too)
	**/
	public static function print(text:String, output:Output = Sys.stdout()) {
		if (Sys.systemName() == "Windows" || !Configuration.USE_COLORS_IN_LOGS) {
			output.writeString(text);
			output.flush();
			return;
		}

		var out = new StringBuf();
		var i = 0;
		var colored = false;

		while (i < text.length) {
			var c = text.charAt(i);

			if (c == "§") {
				i++;
				out.add(String.fromCharCode(27));
				out.add('[');
				colored = true;
				continue;
			}

			out.add(c);
			i++;
		}

		if (colored)
			out.add("\x1b[0m");

		output.writeString(out.toString());
		output.flush();
	}
}

private typedef LevelStyle = {
	label:String,
	badge:String,
	text:String,
	stderr:Bool
}

class Logger {
	static inline var RESET = "\x1B[0m";
	static inline var DIM = "\x1B[2m";

	static final lock = new Mutex();

	public static function info(?p:PosInfos, ...args:Dynamic)
		write({
			label: "INFO ",
			badge: "§94m",
			text: "§97m",
			stderr: false
		}, p, ...args);

	public static function warn(?p:PosInfos, ...args:Dynamic)
		write({
			label: "WARN ",
			badge: "§1;93m",
			text: "§0;33m",
			stderr: true
		}, p, ...args);

	public static function error(?p:PosInfos, ...args:Dynamic)
		write({
			label: "ERROR",
			badge: "§1;91m",
			text: "§0;31m",
			stderr: true
		}, p, ...args);

	public static function debug(?p:PosInfos, ...args:Dynamic) {
		if (!Configuration.SHOW_DEBUG_LOGS)
			return;
		write({
			label: "DEBUG",
			badge: "§1;95m",
			text: "§0;97m",
			stderr: false
		}, p, ...args);
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
			AnsiPrinter.print(line + "\n", out);
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

	public static function getTerminalSize():{cols:Int, rows:Int} {
		try {
			if (Sys.systemName() == "Windows") {
				var p = new sys.io.Process("mode", ["con"]);
				var out = p.stdout.readAll().toString();
				p.close();
				var nums = new Array<Int>();
				var re = ~/\d+/;
				var rest = out;
				while (re.match(rest)) {
					var n = Std.parseInt(re.matched(0));
					if (n == null)
						throw Error.Custom("Couldnt parse the output of 'mode con'.");
					nums.push(n);
					rest = re.matchedRight();
				}

				if (nums.length >= 2 && nums[0] > 0 && nums[1] > 0)
					return {cols: nums[1], rows: nums[0]};
			} else {
				var p = new sys.io.Process("sh", ["-c", "stty size < /dev/tty 2>/dev/null"]);
				var out = StringTools.trim(p.stdout.readAll().toString());
				p.close();
				var parts = out.split(" ");
				if (parts.length == 2) {
					var r = Std.parseInt(parts[0]);
					var c = Std.parseInt(parts[1]);
					if (r != null && c != null && r > 0 && c > 0)
						return {cols: c, rows: r};
				}
			}
		} catch (e:Dynamic) {
			Logger.debug(e);
		}
		// in case the above fails
		var c = Std.parseInt(Sys.getEnv("COLUMNS") + "");
		var r = Std.parseInt(Sys.getEnv("LINES") + "");
		if (c != null && r != null && c > 0 && r > 0)
			return {cols: c, rows: r};
		return {cols: 0, rows: 0};
	}
}
