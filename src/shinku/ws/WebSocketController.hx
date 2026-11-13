package shinku.ws;

import haxe.io.Bytes;
import haxe.crypto.Sha1;
import haxe.crypto.Base64;
import shinku.http.HttpMessages.HttpResponse;
import shinku.handling.RequestHandler.RequestEvent;
import haxe.atomic.AtomicBool;
import hx.concurrent.collection.SynchronizedArray;
import shinku.Console.Logger;
import shinku.scheduling.Executor;
import sys.net.Socket;
import sys.thread.Mutex;
import sys.thread.Thread;

using StringTools;

class WebSocketController {
	/** Longest time the poller waits in select() when nothing is readable. **/
	public static final POLL_TIMEOUT = 0.1;

	final sockets = new SynchronizedArray<WebSocket>();
	final startLock = new Mutex();
	final running = new AtomicBool(true);
	var pollerStarted = false;

	public function new() {}

	public function handleNewSocket(ws:WebSocket) {
		startLock.acquire();
		if (!pollerStarted) {
			pollerStarted = true;
			Thread.create("WebSocket Frame Poller", pollLoop);
		}
		startLock.release();
		sockets.add(ws);
	}

	public function shutdown() {
		running.store(false);
		for (ws in sockets.copy())
			ws.close(1001, "server shutting down");
	}

	function pollLoop() {
		while (running.load()) {
			for (ws in sockets.copy())
				if (ws.isClosed())
					sockets.remove(ws);

			final live = sockets.copy();
			if (live.length == 0) {
				Sys.sleep(POLL_TIMEOUT);
				continue;
			}

			final handles = [for (ws in live) ws.pollHandle()];
			var readable:Array<Socket>;
			try {
				readable = Socket.select(handles, [], [], POLL_TIMEOUT).read;
			} catch (e:Dynamic) {
				Logger.error("WebSocket select failed: " + Std.string(e));
				Sys.sleep(POLL_TIMEOUT);
				continue;
			}

			for (i in 0...live.length) {
				final ws = live[i];
				if (ws == null)
					continue;
				try {
					if (readable.indexOf(handles[i]) >= 0) {
						if (ws.hasReadyPackets())
							scheduleDispatch(ws);
					} else if (ws.isClosing()) {
						if (ws.checkCloseTimeout())
							scheduleDispatch(ws);
					}
				} catch (e:Dynamic) {
					Logger.debug("Dropping a websocket because: " + Std.string(e));
					scheduleDispatch(ws);
				}
			}
		}
	}

	function scheduleDispatch(ws:WebSocket) {
		if (!ws.tryClaimDispatch())
			return;
		Executor.schedule(() -> dispatch(ws));
	}

	function dispatch(ws:WebSocket) {
		while (true) {
			ws.fireEvents();
			ws.releaseDispatch();
			if (!ws.hasPendingEvents() || !ws.tryClaimDispatch())
				break;
		}
	}
}

class WebSocketAction {
	public static function upgrade(event:RequestEvent<Dynamic>, ?appProtocolName:String, onSocket:(sock:WebSocket) -> Void) {
		final req = event.req;
		if (req.status.method != "GET")
			throw new HttpResponse(405, ["allow" => ["GET"]]);

		final connection = req.getHeader("connection");
		final upgrade = req.getHeader("upgrade");
		final key = req.getHeader("sec-websocket-key");
		final version = req.getHeader("sec-websocket-version");
		final clientProtocols = req.getHeader("sec-websocket-protocol"); // optional

		if (connection == null || upgrade == null || key == null || version == null)
			throw new HttpResponse(400, []);
		if (!hasToken(connection, "upgrade") || upgrade.trim().toLowerCase() != "websocket")
			throw new HttpResponse(400, []);
		if (!isValidKey(key))
			throw new HttpResponse(400, []);
		if (version.trim() != "13")
			throw new HttpResponse(426, ["sec-websocket-version" => ["13"]]);

		final responseHeaders = [
			"upgrade" => ["websocket"],
			"connection" => ["Upgrade"],
			"sec-websocket-accept" => [
				Base64.encode(Sha1.make(Bytes.ofString(key.trim() + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))
			]
		];

		var negotiated:Null<String> = null;
		if (appProtocolName != null && clientProtocols != null && clientProtocols.indexOf(appProtocolName) >= 0) {
			negotiated = appProtocolName;
			responseHeaders.set("sec-websocket-protocol", [appProtocolName]);
		}

		final res = new HttpResponse(101, responseHeaders);
		res.onResponseWritten = () -> {
			final sock = new WebSocket(event.url, event.socket.socket, negotiated);
			try {
				onSocket(sock);
			} catch (e:Dynamic) {
				Logger.error("WebSocket handler failed: " + Std.string(e));
				sock.close(1011, "handler failed");
				return;
			}
			event.server.websocketController.handleNewSocket(sock);
		};
		throw res;
	}

	static function hasToken(value:String, token:String):Bool {
		for (t in value.split(",").map(v -> v.trim()).filter(t -> t.length > 0))
			if (t == token)
				return true;
		return false;
	}

	static function isValidKey(key:String):Bool {
		try {
			return Base64.decode(key.trim()).length == 16;
		} catch (_:Dynamic) {
			return false;
		}
	}
}
