package shinku.net;

import sys.net.Host;
import sys.net.Socket;

abstract class NetworkEventHandler {
	public var socket(default, null):Socket;
	public var wasClosureRequested(default, null):Bool;
	public var wasDetachRequested(default, null):Bool;

	public final peer:{host:Host, port:Int};

	public function new(socket:Socket) {
		this.socket = socket;
		this.peer = socket.peer();

		this.wasClosureRequested = false;
		this.wasDetachRequested = false;
	}

	public abstract function handleEvent():Void;

	public function onDisconnect():Void {}

	public function requestClose() {
		this.wasClosureRequested = true;
	}

	public function requestDetatch() {
		this.wasDetachRequested = true;
	}
}
