package shinku.http;

import shinku.Console.Logger;
import shinku.handling.RequestHandler;
import shinku.net.NetworkReactor;
import shinku.scheduling.Executor;
import shinku.ws.WebSocketController;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Thread;

class HttpServer {
	var socket:Socket;
	var running:Bool;

	var networkReactorThread:Null<Thread>;

	public var requestHandler(default, null):RequestHandler;
	public var websocketController(default, null):WebSocketController;
	public var networkReactor(default, null):NetworkReactor;

	public var host(get, never):{host:Host, port:Int};

	public var onListen:Null<() -> Void>;

	function get_host():{host:Host, port:Int} {
		return this.socket.host();
	}

	public function new(host:Host, port:Int) {
		Executor.prepare();

		this.socket = new Socket();
		this.socket.bind(host, port);
		this.running = true;

		this.requestHandler = new RequestHandler();
		this.websocketController = new WebSocketController();
		this.networkReactor = new NetworkReactor();

		this.requestHandler.loadStaticRoutes();
	}

	public function start() {
		this.socket.listen(40);
		var host = this.socket.host();

		if (onListen != null)
			onListen();

		Logger.debug('Server is now listening on http://${host.host}:${host.port}');

		this.networkReactorThread = Thread.create("HttpServer/Reactor", () -> {
			this.networkReactor.run();
		});

		while (running) {
			try {
				this.networkReactor.registerHandler(new HttpEventHandler(this.socket.accept(), this));
			} catch (err) {
				Logger.debug(err.toString());
				Logger.debug(err.stack.toString());
			}
		}
	}

	public function stop() {
		this.running = false;
		this.networkReactor.stop();
	}
}
