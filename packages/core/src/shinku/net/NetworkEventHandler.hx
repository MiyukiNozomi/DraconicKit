package shinku.net;

import haxe.Timer;
import haxe.atomic.AtomicBool;
import shinku.Console.Logger;
import shinku.std.threading.Synchronized;
import sys.net.Host;
import sys.net.Socket;

abstract class NetworkEventHandler {
	public var socket(default, null):Socket;
	public var wasClosureRequested(default, null):AtomicBool;
	public var wasDetachRequested(default, null):AtomicBool;

	public final peer:{host:Host, port:Int};
	public var lastActivity(get, never):Float;

	// NetworkReactor managed, DO NOT TOUCH
	@:internal public var isBusy:Bool;
	@:internal public var syncLastActivity:Synchronized<Float>;

	/**

		Note: this function may throw an exception due to 
		Socket#peer, please wrap it in a try-catch!
	**/
	public function new(socket:Socket) {
		this.socket = socket;
		this.syncLastActivity = new Synchronized(Timer.stamp());
		this.peer = socket.peer();

		this.isBusy = false;

		this.wasClosureRequested = new AtomicBool(false);
		this.wasDetachRequested = new AtomicBool(false);
	}

	public abstract function handleEvent():Void;

	public function onDisconnect():Void {}

	public function requestClose() {
		this.wasClosureRequested.store(true);
	}

	public function requestDetach() {
		this.wasDetachRequested.store(true);
	}

	/**
		# INTERNAL USAGE ONLY!
		do not call!
	**/
	@:internal
	public function forceClose() {
		try
			this.socket.close()
		catch (_) {}

		try
			this.onDisconnect()
		catch (e)
			Logger.error("onDisconnect failed: ", e);
	}

	public function touch() {
		this.syncLastActivity.modify((old) -> {
			return Timer.stamp();
		});
	}

	function get_lastActivity():Float {
		return this.syncLastActivity.access(f -> f);
	}
}
