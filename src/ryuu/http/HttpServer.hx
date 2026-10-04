package ryuu.http;

import ryuu.http.HttpSocket.HttpSocketTimeout;
import ryuu.http.HttpMessages.HttpRequest;
import ryuu.scheduling.Executor;
import ryuu.http.HttpMessages.HttpResponse;
import sys.io.File;
import sys.net.Host;
import sys.net.Socket;

class HttpServer {
	private var socket:Socket;
	private var running:Bool;

	private var executor:Executor;

	public function new(host:Host, port:Int) {
		this.socket = new Socket();
		this.socket.bind(host, port);
		this.running = true;

		this.executor = new Executor();
	}

	public function start() {
		this.socket.listen(40);
		var host = this.socket.host();

		trace("Server is now listening on http://" + host.host + ":" + host.port);
		while (running) {
			try {
				var client = new HttpSocket(this.socket.accept());
				trace("Got client: ", client.socket.peer());
				handleClient(client);
			} catch (err) {
				trace(err.toString());
				trace(err.stack.toString());
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
							trace("Got a broken request!");
							client.socket.close();
							return;
						} else {
							trace(req.status);
						}

						if (req.status.target == "/") {
							throw new HttpResponse(200, {"content-type": "text/html"}, File.read("test.html").readAll());
						} else if (req.status.target == "/test.webp") {
							throw new HttpResponse(200, {"content-type": "image/webp"}, File.read("test.webp"));
						} else {
							throw new HttpResponse(404);
						}
					} catch (err) {
						var res = Std.downcast(err, HttpResponse);
						var timeout = Std.downcast(err, HttpSocketTimeout);

						if (res != null) {
							res.sourceRequest = req;
							trace("Response for ", client.socket.peer(), " is ", res.status);
							client.sendResponse(res);

							var connectionHeader = req != null ? (req.getHeader("connection", "keep-alive")) : "keep-alive";

							if (connectionHeader == "close") {
								client.socket.close();
								return;
							}
						} else {
							if (timeout == null) {
								trace(err.toString());
								trace(err.stack.toString());
							} else {
								trace("Client ", client.socket.peer(), " has timed out.");
							}
							client.socket.close();
							return;
						}
					}
				}
			} catch (err) {
				trace("FATAL: got a unhandled exception when handling a socket!\n" + err.toString());
			}
		});
	}
}
