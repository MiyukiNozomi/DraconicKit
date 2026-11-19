package shinku.net;

import shinku.scheduling.Executor;
import sys.thread.Mutex;
import shinku.Console.Logger;
import shinku.std.io.SocketSelect;
import sys.net.Socket;

class NetworkReactor {
	/** Longest time the poller waits in select() when nothing is readable. **/
	public static final POLL_TIMEOUT = 0.1;

	/** A time in which sockets that had no writes or reads will be booted off. **/
	public static final KEEP_ALIVE_TIMEOUT = 15;

	var handlers:Map<Socket, NetworkEventHandler>;
	var sockets:Array<Socket>;
	var busySockets:Array<Socket>;

	var modifyLock = new Mutex();

	var running = false;

	public function new() {
		this.handlers = new Map();
		this.sockets = new Array();
		this.busySockets = new Array();
	}

	public function registerHandler(handler:NetworkEventHandler) {
		this.modifyLock.acquire();
		handlers[handler.socket] = handler;
		if (!sockets.contains(handler.socket))
			sockets.push(handler.socket);
		this.modifyLock.release();
	}

	public function run() {
		running = true;

		while (running) {
			modifyLock.acquire();
			final candidates = [for (s in sockets) if (!busySockets.contains(s)) s];
			modifyLock.release();

			Logger.debug("Socket count: ", this.sockets.length);
			Logger.debug("Busy socket count: ", this.busySockets.length);

			var readable:Array<Socket>;
			try {
				readable = SocketSelect.select(candidates, [], [], POLL_TIMEOUT).read;
			} catch (e) {
				Logger.debug("Socket select failure, pruning invalid sockets: ", e);
				modifyLock.acquire();
				for (s in candidates) {
					try {
						SocketSelect.select([s], [], [], 0);
					} catch (_) {
						sockets.remove(s);
						handlers.remove(s);
					}
				}
				modifyLock.release();
				continue;
			}
			for (sock in readable) {
				modifyLock.acquire();
				final handler = handlers.get(sock);
				if (handler == null || busySockets.contains(sock)) {
					modifyLock.release();
					continue;
				}
				busySockets.push(sock);
				modifyLock.release();

				final h:NetworkEventHandler = handler;
				final s = sock;
				Executor.schedule(() -> {
					var alive = true;
					try {
						h.handleEvent();
					} catch (e:haxe.io.Eof) {
						alive = false;
					} catch (e) {
						Logger.error("Handler failed, closing socket: ", e);
						alive = false;
					}

					modifyLock.acquire();
					busySockets.remove(s);
					if (!alive || h.wasClosureRequested || h.wasDetachRequested)
						removeSocket(s);
					modifyLock.release();

					if (!alive || h.wasClosureRequested) {
						try
							s.close()
						catch (_) {}
						h.onDisconnect();
					}
				});
			}
		}
	}

	function removeSocket(s:Socket) {
		sockets.remove(s);
		handlers.remove(s);
		busySockets.remove(s);
	}

	public function stop() {
		running = false;
	}
}
