package shinku.std.threading;

import hx.concurrent.lock.RLock;

class Synchronized<T> {
	private var victim:T;
	private final mutex = new RLock();

	public function new(victim:T) {
		this.victim = victim;
	}

	/** fn must not let its argument escape. */
	public function access<R>(fn:T->R):R {
		return locked(() -> fn(victim));
	}

	/** Atomic read-modify-write; fn returns the new victim. */
	public function modify(fn:T->T):Void {
		locked(() -> {
			victim = fn(victim);
			return null;
		});
	}

	/** Replace the victim, return the old one. */
	public function swap(next:T):T {
		return locked(() -> {
			var old = victim;
			victim = next;
			return old;
		});
	}

	private inline function locked<R>(fn:() -> R):R {
		mutex.acquire();
		try {
			var r = fn();
			mutex.release();
			return r;
		} catch (e) {
			mutex.release();
			throw e;
		}
	}
}
