package shinku.http;

import haxe.io.Bytes;
import shinku.ws.WebSocketController;
import sys.net.Host;
import shinku.Console.Logger;
import shinku.handling.RequestHandler;
import shinku.http.HttpMessages.HttpRequest;
import shinku.http.HttpMessages.HttpResponse;
import shinku.http.HttpSocket.HttpSocketTimeout;
import shinku.scheduling.Executor;
import sys.net.Socket;

class HttpServer {
	private var socket:Socket;
	private var running:Bool;

	public var requestHandler(default, null):RequestHandler;

	public var host(get, never):{host:Host, port:Int};

	public var onListen:Null<() -> Void>;

	public var websocketController:WebSocketController;

	public function new(host:Host, port:Int) {
		Executor.prepare();

		this.socket = new Socket();
		this.socket.bind(host, port);
		this.running = true;

		this.requestHandler = new RequestHandler();

		this.requestHandler.loadStaticRoutes();

		this.websocketController = new WebSocketController();
	}

	public function start() {
		this.socket.listen(40);
		var host = this.socket.host();

		if (onListen != null)
			onListen();

		Logger.debug("Server is now listening on http://" + host.host + ":" + host.port);
		while (running) {
			try {
				var client = new HttpSocket(this.socket.accept());
				Logger.debug("Got client: ", client.socket.peer());
				handleClient(client);
			} catch (err) {
				Logger.debug(err.toString());
				Logger.debug(err.stack.toString());
			}
		}
	}

	public function stop() {
		this.running = false;
	}

	private function handleClient(client:HttpSocket) {
		Executor.schedule(() -> {
			try {
				while (true) {
					var req:Null<HttpRequest> = null;
					try {
						req = client.nextRequest();
						if (req == null) {
							Logger.warn("Got a broken request!");
							client.socket.close();
							return;
						} else {
							if (Configuration.ShowDevRequests)
								Logger.info(req.status);
						}

						requestHandler.handleRequest(this, client, req);

						// oh. no response given.. that's bad, really bad. lets report a 503.
						throw new HttpResponse(500, ["content-type" => ["text/plain; charset=utf-8"]],
							Bytes.ofString("Request handler did not throw a response."));
					} catch (err) {
						var res = Std.downcast(err, HttpResponse);
						var timeout = Std.downcast(err, HttpSocketTimeout);

						if (res != null) {
							res.sourceRequest = req;
							Logger.debug("Response for ", client.socket.peer(), " is ", res.status);
							client.sendResponse(res);

							var connectionHeader = req != null ? ((req.getHeader("connection", "keep-alive") + "").toLowerCase()) : "keep-alive";

							if (connectionHeader.indexOf("close") != -1) {
								client.socket.close();
								return;
							}

							try {
								if (res.onResponseWritten != null)
									res.onResponseWritten();
							} catch (e) {
								Logger.error("An exception was thrown inside of the onResponseWritten!\n" + e.toString() + "\n" + e.stack.toString());
							}

							// So, it's switching protocols, that means this thread cannot continue handling it.
							if (res.status == 101) {
								break; // Stop handling this socket, keep it open so the underlying transfer protocol can manage it.
							}
						} else {
							if (timeout == null) {
								Logger.error(err.toString());
								Logger.error(err.stack.toString());
							} else {
								Logger.debug("Client ", client.socket.peer(), " has timed out.");
							}
							client.socket.close();
							return;
						}
					}
				}
			} catch (err) {
				try {
					client.socket.close();
				} catch (e) {
					Logger.debug(e.toString() + "\n" + e.stack.toString());
				}
				Logger.error("FATAL: got a unhandled exception when handling a socket!\n" + err.toString() + "\n" + err.stack.toString());
			}
		});
	}

	function get_host():{host:Host, port:Int} {
		return this.socket.host();
	}
}
