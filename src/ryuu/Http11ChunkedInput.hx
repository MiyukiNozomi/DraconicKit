package ryuu;

import haxe.io.Error;
import haxe.io.Eof;
import haxe.io.Bytes;
import haxe.io.BytesData;
import haxe.io.BytesBuffer;
import haxe.io.Input;
import sys.net.Socket;

class Http11ChunkedInput extends Input {
	private var socket:HttpSocket;
	private var localBuffer:Bytes;

	private var cursor:Int;
	private var currentChunkLength:Int;

	public function new(socket:HttpSocket) {
		this.cursor = 0;
		this.currentChunkLength = 0;
		this.socket = socket;
		this.localBuffer = Bytes.alloc(65535);
	}

	public override function readByte():Int {
		this.readChunked();

		if (cursor >= this.currentChunkLength) {
			throw new haxe.io.Eof();
		}

		return this.localBuffer.get(cursor++);
	}

	private var hasReachedEOF = false;

	private function consumeCRLF() {
		var cr = socket.socket.input.readByte();
		var lf = socket.socket.input.readByte();
		if (cr != 13 || lf != 10)
			throw Error.Custom("Invalid chunk terminator");
	}

	private function readChunked() {
		if (hasReachedEOF)
			throw new haxe.io.Eof();
		if (this.cursor < this.currentChunkLength)
			return;

		var lengthBuff = this.socket.readUntilCRLF();
		if (lengthBuff == null) {
			return;
		}

		var lengthStr = lengthBuff.toString();
		var cutOff = lengthStr.indexOf(";");
		if (cutOff != -1) {
			// technically parseInt will ignore everything from ; and onwards.
			// but lets cut it in case we want to do something about this in the future.
			// TODO.
			lengthStr = lengthStr.substring(0, cutOff);
		}

		var length = Std.parseInt("0x" + lengthStr);
		trace(length);
		if (length == null) {
			throw Error.Custom("Length is non numeric: " + lengthStr);
		}

		if (length == 0) {
			hasReachedEOF = true;
			this.consumeCRLF();
			throw new haxe.io.Eof();
		}

		if (length > this.localBuffer.length) {
			throw Error.Overflow;
		}

		this.cursor = 0;
		this.currentChunkLength = length;
		this.socket.socket.input.readFullBytes(this.localBuffer, 0, length);
		this.consumeCRLF();
	}
}
