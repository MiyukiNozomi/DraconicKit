package shinku.http;

import haxe.io.Bytes;
import shinku.Console.Logger;
import shinku.handling.RequestHandler;
import shinku.http.HttpMessages.HttpRequest;
import shinku.http.HttpMessages.HttpResponse;
import shinku.http.HttpSocket.HttpSocketTimeout;
import shinku.scheduling.Executor;
import shinku.ws.WebSocketController;
import sys.net.Host;
import sys.net.Socket;

class HttpServer {
	var socket:Socket;
	var running:Bool;

	public var requestHandler(default, null):RequestHandler;

	public var host(get, never):{host:Host, port:Int};

	public var onListen:Null<() -> Void>;

	public var websocketController:WebSocketController;

	function get_host():{host:Host, port:Int} {
		return this.socket.host();
	}

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

		Logger.debug('Server is now listening on http://${host.host}:${host.port}');

		while (running) {
			try {
				handleClient(new HttpSocket(this.socket.accept()));
			} catch (err) {
				Logger.debug(err.toString());
				Logger.debug(err.stack.toString());
			}
		}
	}

	public function stop() {
		this.running = false;
		try {
			this.socket.close();
		} catch (_) {}
	}

	function handleClient(client:HttpSocket) {
		Executor.schedule(() -> {
			Logger.debug("Got client: ", client.socket.peer());
			while (true) {
				var req:Null<HttpRequest> = null;
				try {
					req = client.nextRequest();
					if (req == null) {
						Logger.warn("Got a broken request!");
						client.close();
						return;
					}
					if (Configuration.ShowDevRequests)
						Logger.info(req.status);

					requestHandler.handleRequest(this, client, req);

					// oh. no response given.. that's bad, really bad. lets report a 503.
					throw new HttpResponse(503, ["content-type" => ["text/plain; charset=utf-8"]], Bytes.ofString("Request handler did not throw a response."));
				} catch (err) {
					var res = Std.downcast(err, HttpResponse);

					if (res == null) {
						if (Std.downcast(err, HttpSocketTimeout) != null) {
							Logger.debug("Client ", client.socket.peer(), " has timed out.");
						} else {
							Logger.error(err.toString());
							Logger.error(err.stack.toString());
						}
						client.close();
						return;
					}

					res.sourceRequest = req;
					Logger.debug("Response for ", client.socket.peer(), " is ", res.status);
					client.sendResponse(res);

					if (res.forceSocketClosure || wantsConnectionClose(req)) {
						client.close();
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
						// Stop handling this socket, keep it open so the underlying transfer protocol can manage it.
						break;
					}
				}
			}
		});
	}

	static function wantsConnectionClose(req:Null<HttpRequest>):Bool {
		if (req == null)
			return false;

		final chunked = Std.downcast(req.payload, Http11ChunkedInput);
		if (chunked != null && !chunked.isFinished) {
			Logger.debug("Warning: request for", req.status, "will e forcefully closed as the chunked transfer input stream was not fully consumed.");
			return true;
		}

		final connection = (req.getHeader("connection", "keep-alive") + "").toLowerCase();
		return connection.indexOf("close") != -1;
	}
}
