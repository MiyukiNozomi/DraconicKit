/**
	This class is broken, and needs fixing ASAP.

	TODO.
**/

package shinku.std;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;
import haxe.io.Output;
import sys.thread.Deque;

class PipeOutput extends Output {
	var isClosed = false;

	public var input(default, null):BytesBufferInput;

	public function new() {
		input = new BytesBufferInput();
	}

	override function writeByte(c:Int):Void {
		if (this.isClosed)
			return;
		input.push(c);
	}

	override function writeBytes(bytes:Bytes, pos:Int, len:Int):Int {
		if (this.isClosed)
			return 0;

		if (len == 0)
			return 0;

		for (i in pos...(pos + len)) {
			input.push(bytes.get(i));
		}
		return len;
	}

	override function close():Void {
		if (isClosed)
			return;
		isClosed = true;
		input.close();
	}
}

class BytesBufferInput extends Input {
	final queue = new Deque<Int>();
	var closed = false;
	var eof = false;

	public function new() {}

	public function push(byte:Int):Void {
		if (closed)
			throw new PipeClosed("");
		queue.add(byte);
	}

	override function readByte():Int {
		if (eof)
			throw new Eof();
		final b = queue.pop(true);
		if (b < 0) {
			eof = true;
			throw new Eof();
		}
		return b;
	}

	override function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (len == 0)
			return 0;
		if (eof)
			throw new Eof();
		final first = queue.pop(true);
		if (first < 0) {
			eof = true;
			throw new Eof();
		}
		s.set(pos, first);
		var n = 1;
		while (n < len) {
			final b = queue.pop(false);
			if (b < 0) {
				if (closed)
					eof = true;
				break;
			}
			s.set(pos + n, b);
			n++;
		}
		return n;
	}

	override function close():Void {
		if (closed)
			return;
		closed = true;
		queue.add(-5);
	}
}

class PipeClosed extends Exception {}
