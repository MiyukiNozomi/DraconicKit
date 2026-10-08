package ryuu.http;

import ryuu.Console.Logger;
import ryuu.handling.RequestHandler;
import ryuu.http.HttpMessages.HttpRequest;
import ryuu.http.HttpMessages.HttpResponse;
import ryuu.http.HttpSocket.HttpSocketTimeout;
import ryuu.scheduling.Executor;
import sys.net.Host;
import sys.net.Socket;

class HttpServer {
	private var socket:Socket;
	private var running:Bool;

	private var executor:Executor;

	public var requestHandler(default, null):RequestHandler;

	public function new(host:Host, port:Int) {
		this.socket = new Socket();
		this.socket.bind(host, port);
		this.running = true;

		this.executor = new Executor();
		this.requestHandler = new RequestHandler();

		this.requestHandler.loadStaticRoutes();
	}

	public function start() {
		this.socket.listen(40);
		var host = this.socket.host();

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

	private function handleClient(client:HttpSocket) {
		this.executor.schedule(() -> {
			try {
				while (true) {
					var req:Null<HttpRequest> = null;
					try {
						req = client.nextRequest();
						if (req == null) {
							Logger.debug("Got a broken request!");
							client.socket.close();
							return;
						} else {
							Logger.debug(req.status);
						}

						requestHandler.handleRequest(client, req);
					} catch (err) {
						var res = Std.downcast(err, HttpResponse);
						var timeout = Std.downcast(err, HttpSocketTimeout);

						if (res != null) {
							res.sourceRequest = req;
							Logger.debug("Response for ", client.socket.peer(), " is ", res.status);
							client.sendResponse(res);
							//	trace("Sent.");

							var connectionHeader = req != null ? ((req.getHeader("connection", "keep-alive") + "").toLowerCase()) : "keep-alive";

							if (connectionHeader.indexOf("close") != -1) {
								client.socket.close();
								return;
							}
						} else {
							if (timeout == null) {
								Logger.debug(err.toString());
								Logger.debug(err.stack.toString());
							} else {
								Logger.debug("Client ", client.socket.peer(), " has timed out.");
							}
							client.socket.close();
							return;
						}
					}
				}
			} catch (err) {
				Logger.debug("FATAL: got a unhandled exception when handling a socket!\n" + err.toString());
			}
		});
	}
}
