package ryuu.http;

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

				var req = client.nextRequest();
				trace(req);

				if (req == null) {
					client.socket.close();
					continue;
				}

				var payload = req.payload;
				if (payload != null) {
					var file = File.write("payload.bin");
					file.writeInput(payload);
					file.close();
				} else {
					trace("Request has no payload.");
				}
			} catch (err) {
				trace(err.toString());
				trace(err.stack.toString());
			}
		}
	}
}
