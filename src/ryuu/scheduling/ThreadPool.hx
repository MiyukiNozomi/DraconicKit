/*
 * Copyright (C)2005-2019 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/**
	This technically was on Haxe 4.3.7, but was.. apperantely nuked in the Haxe 5 preview. So I bought it back!
**/
package ryuu.scheduling;

import haxe.io.Error;
import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Deque;
#if (!target.threaded) #error "This class is not available on this target" #end
import haxe.Exception;

/**
	Thread pool with a constant amount of threads.
	Threads in the pool will exist until the pool is explicitly shut down.
**/
class ThreadPool {
	/* Amount of threads in this pool. */
	public var threadsCount(get, null):Int;

	function get_threadsCount():Int
		return threadsCount;

	/** Indicates if `shutdown` method of this pool has been called. */
	public var isShutdown(get, never):Bool;

	var _isShutdown = false;

	function get_isShutdown():Bool
		return _isShutdown;

	final pool:Array<Worker>;
	final poolMutex = new Mutex();
	final queue = new Deque<() -> Void>();

	/**
		Create a new thread pool with `threadsCount` threads.
	**/
	public function new(threadsCount:Int):Void {
		if (threadsCount < 1)
			throw Error.Custom('FixedThreadPool needs threadsCount to be at least 1.');
		this.threadsCount = threadsCount;
		pool = [for (i in 0...threadsCount) new Worker(i, queue)];
	}

	/**
		Submit a task to run in a thread.

		Throws an exception if the pool is shut down.
	**/
	public function run(task:() -> Void):Void {
		if (_isShutdown)
			throw Error.Custom('Task is rejected. Thread pool is shut down.');
		if (task == null)
			throw Error.Custom('Task to run must not be null.');
		queue.add(task);
	}

	/**
		Initiates a shutdown.
		All previousely submitted tasks will be executed, but no new tasks will
		be accepted.

		Multiple calls to this method have no effect.
	**/
	public function shutdown():Void {
		if (_isShutdown)
			return;
		_isShutdown = true;
		for (_ in pool) {
			queue.add(shutdownTask);
		}
	}

	static function shutdownTask():Void {
		throw new ShutdownException('');
	}
}

private class ShutdownException extends Exception {}

// nasty I know..

@:nullSafety(Off)
private class Worker {
	var workerId:Int;
	var thread:Thread;
	final queue:Deque<Null<() -> Void>>;

	public function new(workerId:Int, queue:Deque<Null<() -> Void>>) {
		this.queue = queue;
		thread = Thread.create('Worker/${workerId}', loop);
	}

	function loop() {
		try {
			while (true) {
				var task = queue.pop(true);
				task();
			}
		} catch (_:ShutdownException) {} catch (e) {
			thread = Thread.create(loop);
			throw e;
		}
	}
}
