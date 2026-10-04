package ryuu.http;

import ryuu.http.HttpMessages.HttpResponse;
import sys.io.File;
import sys.net.Host;
import sys.net.Socket;

class HttpServer {
	private var socket:Socket;
	private var running:Bool;

	public function new(host:Host, port:Int) {
		this.socket = new Socket();
		this.socket.bind(host, port);
		this.running = true;
	}

	public function start() {
		this.socket.listen(40);
		var host = this.socket.host();

		trace("Server is now listening on http://" + host.host + ":" + host.port);
		while (running) {
			try {
				var client = new HttpSocket(this.socket.accept());
				trace("Got client: ", client.socket.peer());

				try {
					var req = client.nextRequest();

					if (req == null) {
						trace("Got a broken request!");
						client.socket.close();
						continue;
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
				} catch (res:HttpResponse) {
					trace("Response for ", client.socket.peer(), " is ", res.status);
					client.sendResponse(res);
				}
				client.socket.close();
			} catch (err) {
				trace(err.toString());
				trace(err.stack.toString());
			}
		}
	}
}
