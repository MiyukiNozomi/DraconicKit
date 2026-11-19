package shinku.net;

import haxe.atomic.AtomicBool;
import haxe.io.Error;
import shinku.Console.Logger;
import shinku.scheduling.Executor;
import shinku.std.io.SocketSelect;
import sys.net.Socket;
import sys.thread.Mutex;

class NetworkReactor {
	/** Longest time the poller waits in select() when nothing is readable. **/
	public static final POLL_TIMEOUT = 0.1;

	/** A time in which sockets that had no writes or reads will be booted off. **/
	public static final KEEP_ALIVE_TIMEOUT = 15;

	var handlers:Map<Socket, NetworkEventHandler>;

	var modifyLock = new Mutex();

	var isRunning = new AtomicBool(true);

	public function new() {
		this.handlers = new Map();
	}

	public function registerHandler(handler:NetworkEventHandler) {
		this.modifyLock.acquire();
		if (this.handlers.exists(handler.socket)) {
			this.modifyLock.release();
			throw Error.Custom("Socket already registered in this Network Reactor!");
		}

		handlers[handler.socket] = handler;
		this.modifyLock.release();
	}

	public function run() {
		try {
			while (isRunning.load()) {
				poll();
			}
		} catch (e:Dynamic) {
			drain();
			throw e;
		}
		drain();
	}

	public function stop() {
		isRunning.store(false);
	}

	function poll() {
		final now = haxe.Timer.stamp();
		final candidates:Array<Socket> = [];
		final expired:Array<NetworkEventHandler> = [];
		final detached:Array<Socket> = [];

		modifyLock.acquire();
		for (s => h in handlers) {
			if (h.isBusy)
				continue;
			if (h.wasDetachRequested.load()) {
				detached.push(s);
			} else if (h.wasClosureRequested.load() || (now - h.lastActivity) > KEEP_ALIVE_TIMEOUT) {
				expired.push(h);
			} else {
				candidates.push(s);
			}
		}
		for (s in detached)
			removeSocket(s);
		for (h in expired)
			removeSocket(h.socket);

		#if draconicdev
		// Logger.debug("Socket count: ", this.handlers.size());
		// Logger.debug("Busy socket count: ", this.handlers.size() - candidates.length);
		#end

		modifyLock.release();

		for (h in expired)
			h.forceClose();

		if (candidates.length == 0) {
			Sys.sleep(POLL_TIMEOUT);
			return;
		}

		var readable:Array<Socket>;
		try {
			readable = SocketSelect.select(candidates, [], [], POLL_TIMEOUT).read;
		} catch (e) {
			Logger.debug("Socket select failure, pruning invalid sockets: ", e);
			final dead = [for (s in candidates) if (!isDead(s)) s]; // see below
			final doomed:Array<NetworkEventHandler> = [];

			if (dead.length == 0) {
				Sys.sleep(POLL_TIMEOUT);
				return;
			}

			modifyLock.acquire();
			for (s in dead) {
				final h = handlers.get(s);
				removeSocket(s);
				if (h != null)
					doomed.push(h);
			}
			modifyLock.release();
			for (h in doomed) {
				h.forceClose();
			}
			return;
		}
		for (sock in readable) {
			modifyLock.acquire();
			final handler = handlers.get(sock);
			if (handler == null || handler.isBusy) {
				modifyLock.release();
				continue;
			}
			handler.isBusy = true;
			modifyLock.release();

			final h:NetworkEventHandler = handler;
			final s = sock;
			Executor.schedule(() -> {
				var alive = true;
				try {
					h.handleEvent();
					h.touch();
				} catch (e:haxe.io.Eof) {
					alive = false;
				} catch (e) {
					Logger.error("Handler failed, closing socket: ", e);
					alive = false;
				}

				modifyLock.acquire();
				h.isBusy = false;
				final closeNow = !alive || h.wasClosureRequested.load();
				if (closeNow || h.wasDetachRequested.load())
					removeSocket(s);
				modifyLock.release();

				if (closeNow) {
					h.forceClose();
				}
			});
		}
	}

	function removeSocket(s:Socket) {
		handlers.remove(s);
	}

	function isDead(s:Socket):Bool {
		try {
			SocketSelect.select([s], [], [], 0);
			return false;
		} catch (_) {
			return true;
		}
	}

	function drain() {
		final toClose:Array<NetworkEventHandler> = [];

		modifyLock.acquire();
		for (s => h in handlers) {
			h.requestClose();
			if (!h.isBusy) {
				toClose.push(h);
			}
		}
		for (h in toClose)
			removeSocket(h.socket);
		modifyLock.release();

		for (h in toClose)
			h.forceClose();
	}
}
