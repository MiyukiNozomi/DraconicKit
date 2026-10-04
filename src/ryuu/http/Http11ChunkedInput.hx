package ryuu.http;

import ryuu.http.HttpMessages.HttpResponse;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Error;
import haxe.io.Input;

class Http11ChunkedInput extends Input {
	private var socket:HttpSocket;
	private var localBuffer:Bytes;

	private var cursor:Int;
	private var currentChunkLength:Int;

	private var totalReadAmount:Int;

	public function new(socket:HttpSocket) {
		this.cursor = 0;
		this.totalReadAmount = 0;
		this.currentChunkLength = 0;
		this.socket = socket;
		this.localBuffer = Bytes.alloc(HttpSocket.MAX_CHUNKED_TRANSFER_BLOCK_SIZE);
	}

	public override function readByte():Int {
		if (hasReachedEOF)
			throw new haxe.io.Eof();
		this.readChunked();

		if (cursor >= this.currentChunkLength) {
			throw new haxe.io.Eof();
		}

		return this.localBuffer.get(cursor++);
	}

	public override function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (hasReachedEOF)
			throw new Eof();

		if (pos < 0 || len < 0 || pos + len > s.length)
			throw Error.OutsideBounds;

		var read = 0;

		try {
			while (read < len) {
				if (cursor >= currentChunkLength) {
					readChunked();
				}

				var available = currentChunkLength - cursor;
				var amount = Std.int(Math.min(available, len - read));

				s.blit(pos + read, localBuffer, cursor, amount);

				cursor += amount;
				read += amount;
			}
		} catch (e:Eof) {}

		// yes. i have to do this.
		// otherwise anything that uses this input will just straight up explode.
		if (read == 0)
			throw new Eof();
		return read;
	}

	private var hasReachedEOF = false;

	// yes, we do not in fact, do anything with trailers.
	// the browser will naturally not send this type of thing.
	// we might choose to do it in our side when responding, however? this is a input stream,
	// that should only be implemented in an output stream.
	private function consumeTrailers() {
		while (true) {
			var line = socket.readUntilCRLF();

			if (line == null)
				throw new Eof();

			if (line.length == 0)
				return;
		}
	}

	private function consumeCRLF() {
		var cr = socket.socket.input.readByte();
		var lf = socket.socket.input.readByte();
		if (cr != 13 || lf != 10)
			throw Error.Custom("Invalid chunk terminator");
	}

	private function readChunked() {
		if (this.cursor < this.currentChunkLength || hasReachedEOF)
			return;

		var lengthBuff = this.socket.readUntilCRLF(HttpSocket.MAX_CHUNKED_TRANSFER_BLOCK_SIZE);
		if (lengthBuff == null) {
			throw new haxe.io.Eof();
		}

		var lengthStr = lengthBuff.toString();
		var cutOff = lengthStr.indexOf(";");
		if (cutOff != -1) {
			// technically parseInt will ignore everything from ; and onwards.
			// but lets cut it in case we want to do something about this in the future.
			// TODO.
			lengthStr = lengthStr.substring(0, cutOff);
		}

		if (!(~/^[0-9a-fA-F]+$/).match(lengthStr)) {
			throw Error.Custom("Bad length str in HTTP 1.1 chunk: " + lengthStr);
		}

		var length = Std.parseInt("0x" + lengthStr);

		if (length == null) {
			throw Error.Custom("Length is non numeric: " + lengthStr);
		}

		if (length == 0) {
			hasReachedEOF = true;
			this.consumeTrailers();
			throw new haxe.io.Eof();
		}

		if (length > this.localBuffer.length) {
			throw Error.Overflow;
		}

		totalReadAmount += length;
		if (totalReadAmount > HttpSocket.MAXIMUM_PAYLOAD_LENGTH) {
			throw new HttpResponse(413);
		}

		this.cursor = 0;
		this.currentChunkLength = length;
		this.socket.socket.input.readFullBytes(this.localBuffer, 0, length);
		this.consumeCRLF();
	}
}
