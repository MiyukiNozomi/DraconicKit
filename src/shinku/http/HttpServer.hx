package shinku.http;

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

	private var executor:Executor;

	public var requestHandler(default, null):RequestHandler;

	public var host(get, never):{host:Host, port:Int};

	public var onListen:Null<() -> Void>;

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

	private function handleClient(client:HttpSocket) {
		this.executor.schedule(() -> {
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

						requestHandler.handleRequest(client, req);
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
				Logger.error("FATAL: got a unhandled exception when handling a socket!\n" + err.toString());
			}
		});
	}

	function get_host():{host:Host, port:Int} {
		return this.socket.host();
	}
}
