package shinku.std.io;

import sys.net.Socket;
#if jvm
import java.net.Socket as JSocket;
#end

/**
 * JVM polyfill for sys.net.Socket.select.
 *
 * Come on haxe! implement it!
 */
class SocketSelect {
	static inline final POLL_INTERVAL = 0.001;

	public static function select(read:Array<Socket>, write:Array<Socket>, others:Array<Socket>,
			?timeout:Float):{read:Array<Socket>, write:Array<Socket>, others:Array<Socket>} {
		#if jvm
		final deadline = timeout == null ? null : haxe.Timer.stamp() + timeout;

		while (true) {
			final readable = [for (s in read) if (isReadable(s)) s];
			if (readable.length > 0 || (deadline != null && haxe.Timer.stamp() >= deadline)) {
				return {
					read: readable,
					write: write.copy(),
					others: []
				};
			}
			Sys.sleep(POLL_INTERVAL);
		}
		#else
		return Socket.select(read, write, others, timeout);
		#end
	}

	#if jvm
	static function isReadable(s:Socket):Bool {
		try {
			final js = javaSocket(s);
			if (js.isClosed())
				return false;
			return js.getInputStream().available() > 0;
		} catch (e:Dynamic) {
			return true;
		}
	}

	static function javaSocket(s:Socket):JSocket {
		final js:Dynamic = Reflect.field(s, "sock");
		if (js == null)
			throw "sys.net.Socket: underlying java.net.Socket not found";
		return js;
	}
	#end
}
