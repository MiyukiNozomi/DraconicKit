package shinku.std;

import haxe.io.BytesBuffer;
import haxe.Exception;
import haxe.atomic.AtomicBool;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;
import haxe.io.Output;
import sys.thread.Deque;

/**
	This is used so that you can pipe something as a stream into a haxe Input
	To extract the input, access the `input` field of this class.

	### note: this Output stream requires flushing.
**/
class PipeOutput extends Output {
	final isClosed = new AtomicBool(false);
	var buffer = new BytesBuffer();

	public var input(default, null):BytesBufferInput;

	public function new() {
		input = new BytesBufferInput();
	}

	inline function checkOpen():Void {
		if (isClosed.load())
			throw new PipeClosed("");
	}

	override function writeByte(c:Int):Void {
		checkOpen();
		buffer.addByte(c);
	}

	override function writeBytes(bytes:Bytes, pos:Int, len:Int):Int {
		checkOpen();
		if (pos < 0 || len < 0 || pos + len > bytes.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;
		buffer.addBytes(bytes, pos, len);
		return len;
	}

	override function flush():Void {
		if (buffer.length == 0)
			return;
		final chunk = buffer.getBytes();
		buffer = new BytesBuffer();
		input.push(chunk);
	}

	override function close():Void {
		if (isClosed.load())
			return;
		try {
			flush();
		} catch (_:PipeClosed) {}
		isClosed.store(true);
		input.close();
	}
}

class BytesBufferInput extends Input {
	static final EOF_MARK:Bytes = Bytes.alloc(0);

	final queue = new Deque<Bytes>();
	var closed = new AtomicBool(false);

	var eof = false;
	var current:Null<Bytes> = null;
	var offset = 0;

	public function new() {}

	public function push(chunk:Bytes):Void {
		if (closed.load())
			throw new PipeClosed("");
		if (chunk.length == 0)
			return;
		queue.add(chunk);
	}

	function refill(block:Bool):Bool {
		if (eof)
			return false;
		final chunk = queue.pop(block);
		if (chunk == null)
			return false;
		if (chunk == EOF_MARK) {
			eof = true;
			return false;
		}
		current = chunk;
		offset = 0;
		return true;
	}

	inline function exhausted():Bool {
		return current == null || offset >= current.length;
	}

	override function readByte():Int {
		while (exhausted())
			if (!refill(true))
				throw new Eof();
		return current.get(offset++);
	}

	override function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length)
			throw haxe.io.Error.OutsideBounds;
		if (len == 0)
			return 0;

		while (exhausted())
			if (!refill(true))
				throw new Eof();

		var n = 0;
		while (n < len) {
			if (current == null || (exhausted() && !refill(false)))
				break;
			final take = min(len - n, current.length - offset);
			s.blit(pos + n, current, offset, take);
			offset += take;
			n += take;
		}
		return n;
	}

	override function close():Void {
		if (closed.load())
			return;
		closed.store(true);
		queue.add(EOF_MARK);
	}

	static inline function min(a:Int, b:Int):Int {
		return a < b ? a : b;
	}
}

class PipeClosed extends Exception {}
