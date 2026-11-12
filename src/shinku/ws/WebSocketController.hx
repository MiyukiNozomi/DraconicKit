package shinku.ws;

import shinku.scheduling.Executor;
import haxe.atomic.AtomicBool;
import hx.concurrent.collection.SynchronizedArray;
import haxe.io.Error;
import haxe.io.Bytes;
import haxe.crypto.Sha1;
import haxe.crypto.Base64;
import shinku.Console.Logger;
import shinku.handling.RequestHandler.RequestEvent;
import shinku.http.HttpMessages.HttpResponse;
import shinku.http.HttpServer;
import sys.thread.Thread;

class WebSocketController {
	// TODO: make this configurable?
	public static final WS_SOCKET_SLEEP_TIME = 0.1;

	public var httpServer:Null<HttpServer>;

	// Initially null because this server might not be using web sockets.
	private var worker:Null<Thread>;

	private var running = true;
	private var hasWorker:AtomicBool;
	private var packetPollThread:Null<Thread>;

	private var sockets:SynchronizedArray<WebSocket>;

	public function new() {
		this.httpServer = null;
		this.worker = null;
		this.hasWorker = new AtomicBool(false);
		this.sockets = new SynchronizedArray();
	}

	public function handleNewSocket(ws:WebSocket) {
		this.ensureWorkersExist();
		this.sockets.add(ws);
	}

	function ensureWorkersExist() {
		if (hasWorker.load())
			return;
		hasWorker.store(true);
		this.packetPollThread = Thread.create("WebSocket Frame Poller", () -> {
			var hadNoPackets = true;

			while (running) {
				for (worker in this.sockets.copy()) {
					try {
						if (worker.hasReadyPackets()) {
							hadNoPackets = false;
							// and now.. we fire!
							Executor.schedule(() -> worker.fireEvents());
						}
					} catch (e) {
						Logger.debug("Dropping a websocket because: ", Std.string(e));
						if (!this.sockets.remove(worker)) {
							Logger.error("Could not remove a websocket from the controller after it has disconnected!");
						}
					}
				}

				if (hadNoPackets)
					Sys.sleep(WS_SOCKET_SLEEP_TIME);
			}
		});
	}
}

class WebSocketAction {
	public static function upgrade(event:RequestEvent<Dynamic>, ?appProtocolName:String, onSocket:(sock:WebSocket) -> Void) {
		if (event.req.status.method != "GET") {
			throw Error.Custom("You're not supposed to upgrade connections with a non-GET method.");
		}

		var connection = event.req.getHeader("connection");
		var upgrade = event.req.getHeader("upgrade");
		var websocketKey = event.req.getHeader("sec-websocket-key");
		var websocketProtocol = event.req.getHeader("sec-websocket-protocol");
		var websocketVersion = event.req.getHeader("sec-websocket-version");
		if (connection == null || upgrade == null || websocketKey == null || websocketProtocol == null || websocketVersion == null) {
			#if dev
			Logger.warn("Request", event.req.status.method, event.req.status.target,
				"is missing mandatory headers for a websocket upgrade handshake. (this warning will not appear in production)");
			#end
			throw new HttpResponse(400, []);
		}

		if (websocketVersion != "13") {
			#if dev
			Logger.warn("Request", event.req.status.method, event.req.status.target, "has sent an incorrect version string",
				websocketVersion + ". (this warning will not appear in production)");
			#end
			throw new HttpResponse(400, [], Bytes.ofString("Bad Sec-WebSocket-Version. Expected 13 got " + websocketVersion));
		}

		var responseHeaders = [
			"sec-websocket-accept" => [
				Base64.encode(Sha1.make(Bytes.ofString(websocketKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))
			]
		];

		if (appProtocolName != null)
			responseHeaders.set("sec-websocket-protocol", [appProtocolName]);

		final res = new HttpResponse(101, responseHeaders);

		res.onResponseWritten = () -> {
			var sock = new WebSocket(event.url, event.socket.socket, appProtocolName);
			event.server.websocketController.handleNewSocket(sock);
			onSocket(sock);
		};
		throw res;
	}
}
