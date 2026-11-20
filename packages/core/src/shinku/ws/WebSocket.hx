package shinku.ws;

import sys.thread.Mutex;
import haxe.Exception;
import haxe.Timer;
import haxe.extern.EitherType;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Error;
import shinku.std.URL;
import shinku.std.threading.Synchronized;
import sys.net.Socket;

enum WebSocketReadyState {
	/** Kept for compliance only. The handshake is complete before a WebSocket is handed out. **/
	Connecting;

	Open;
	Closing;
	Closed;
}

typedef CloseInfo = {
	code:Int,
	reason:String
}

typedef MessageHandlers = {
	?onText:String->Void,
	?onBytes:Bytes->Void,
	?onClose:CloseInfo->Void
}

private enum PendingEvent {
	TextMessage(text:String);
	BytesMessage(bytes:Bytes);
	CloseEvent(info:CloseInfo);
}

private class OpCode {
	public static final Continuation = 0;
	public static final Text = 1;
	public static final Binary = 2;
	public static final Close = 8;
	public static final Ping = 9;
	public static final Pong = 10;
}

private class StatusCode {
	public static final NormalClosure = 1000;
	public static final ProtocolError = 1002;
	public static final UnsupportedData = 1003;
	public static final NoStatusReceived = 1005;
	public static final AbnormalClosure = 1006;
	public static final InvalidPayloadData = 1007;
	public static final MessageTooBig = 1009;
}

/**
	A server-oriented WebSocket implementation.

	Incoming bytes are buffered and frames are parsed only once they are complete,
	so partial reads never desynchronise the stream.

	@author suisei
**/
class WebSocket {
	public static final WS_SOCKET_TIMEOUT = 1.0;
	public static final WS_SOCKET_POKE_TIMEOUT = 0.1;

	/** Seconds to wait for the peer to answer our Close frame before dropping TCP. **/
	public static final WS_CLOSE_TIMEOUT = 2.0;

	static final READ_CHUNK_SIZE = 8192;

	/**
		Protocol accepted by the server, or an empty string if protocols was not specified in the WebSocket constructor.
	**/
	public var protocol(default, null):String;

	/**
		Extensions accepted by the server.

		Currently unimplemented in DraconicKit. there is no support for websocket extensions.
	**/
	public var extensions(default, null):String = "";

	/**
		The current state of the connection.
	**/
	public var readyState(default, null):WebSocketReadyState = Open;

	/**
		The absolute URL of the WebSocket.
	**/
	public var url:URL;

	public var onTextMessage(never, set):Null<String->Void>;
	public var onBytesMessage(never, set):Null<Bytes->Void>;
	public var onClose(never, set):Null<CloseInfo->Void>;

	final socket:Synchronized<Socket>;
	final handlers:Synchronized<MessageHandlers>;
	final dispatchLock = new Mutex();
	var dispatching = false;

	var rx:Bytes = Bytes.alloc(READ_CHUNK_SIZE);
	var rxStart = 0;
	var rxEnd = 0;
	var fragmentOpcode = -1;
	var fragmentBuffer:Null<BytesBuffer> = null;
	var fragmentSize = 0;
	var pending:Array<PendingEvent> = [];

	var closeSent = false;
	var closeDeadline = 0.0;

	public function new(url:URL, socket:Socket, appProtocol:Null<String>) {
		this.url = url;
		this.protocol = appProtocol ?? "";
		this.socket = new Synchronized(socket);
		this.handlers = new Synchronized<MessageHandlers>({});
		this.socket.access(s -> s.setTimeout(WS_SOCKET_TIMEOUT));
	}

	function set_onTextMessage(v:Null<String->Void>):Null<String->Void> {
		handlers.access(h -> {
			h.onText = v;
		});
		return v;
	}

	function set_onBytesMessage(v:Null<Bytes->Void>):Null<Bytes->Void> {
		handlers.access(h -> {
			h.onBytes = v;
		});
		return v;
	}

	function set_onClose(v:Null<CloseInfo->Void>):Null<CloseInfo->Void> {
		handlers.access(h -> {
			h.onClose = v;
		});
		return v;
	}

	public function send(data:EitherType<String, Bytes>):Void {
		var opcode:Int;
		var payload:Bytes;
		if (Std.isOfType(data, String)) {
			opcode = OpCode.Text;
			payload = Bytes.ofString(cast data);
		} else {
			opcode = OpCode.Binary;
			payload = cast data;
		}

		socket.access(s -> {
			if (readyState != Open)
				throw new WebSocketException("readyState != Open");
			if (!writeFrame(s, true, opcode, payload)) {
				finish(s, StatusCode.AbnormalClosure, "write failed");
				throw new WebSocketException("write failed");
			}
		});
	}

	public function close(code:Int = StatusCode.NormalClosure, ?reason:String):Void {
		socket.access(s -> {
			if (readyState == Open)
				sendClose(s, code, reason);
		});
	}

	/**
		# INTERNAL USAGE ONLY!
		Reads whatever bytes are available and parses complete frames.
		Returns true if events are waiting for `fireEvents()`.
	**/
	@:internal public function hasReadyPackets():Bool {
		return socket.access(s -> {
			if (readyState == Closing && Timer.stamp() > closeDeadline)
				finish(s, StatusCode.AbnormalClosure, "peer did not complete the closing handshake");
			if (readyState != Closed) {
				readFromSocket(s);
				parseFrames(s);
			}
			return pending.length > 0;
		});
	}

	/**
		# INTERNAL USAGE ONLY!
		Dispatches queued events. Handlers run without holding the socket lock.
	**/
	@:internal public function fireEvents():Void {
		final batch = socket.access(s -> {
			final taken = pending;
			pending = [];
			return taken;
		});
		final h = handlers.access(x -> x);

		for (event in batch) {
			switch (event) {
				case TextMessage(text):
					if (h.onText != null)
						h.onText(text);
				case BytesMessage(bytes):
					if (h.onBytes != null)
						h.onBytes(bytes);
				case CloseEvent(info):
					if (h.onClose != null)
						h.onClose(info);
			}
		}
	}

	@:internal public function pollHandle()
		return socket.access(s -> s);

	@:internal public function isClosed()
		return socket.access(_ -> readyState == Closed);

	@:internal public function isClosing()
		return socket.access(_ -> readyState == Closing);

	@:internal public function hasPendingEvents()
		return socket.access(_ -> pending.length > 0);

	@:internal public function tryClaimDispatch() {
		dispatchLock.acquire();
		final ok = !dispatching;
		if (ok)
			dispatching = true;
		dispatchLock.release();
		return ok;
	}

	@:internal public function releaseDispatch():Void {
		dispatchLock.acquire();
		dispatching = false;
		dispatchLock.release();
	}

	/** Returns true if the close deadline passed and a close event was queued. **/
	@:internal public function checkCloseTimeout():Bool {
		return socket.access(s -> {
			if (readyState == Closing && Timer.stamp() > closeDeadline) {
				finish(s, StatusCode.AbnormalClosure, "peer did not complete the closing handshake");
				return true;
			}
			return false;
		});
	}

	function readFromSocket(s:Socket):Void {
		final chunk = Bytes.alloc(READ_CHUNK_SIZE);
		var count = 0;
		var error:Dynamic = null;

		s.setTimeout(WS_SOCKET_POKE_TIMEOUT);
		try {
			count = s.input.readBytes(chunk, 0, READ_CHUNK_SIZE);
		} catch (e:Dynamic) {
			error = e;
		}
		s.setTimeout(WS_SOCKET_TIMEOUT);

		if (error != null) {
			// Nothing arrived within the poke timeout. Not an error.
			if (error == Error.Blocked)
				return;
			// Eof or a real socket failure: the peer is gone.
			finish(s, StatusCode.AbnormalClosure, "connection lost");
			return;
		}
		appendReceived(chunk, count);
	}

	function appendReceived(src:Bytes, count:Int):Void {
		final unread = rxEnd - rxStart;
		if (rxEnd + count > rx.length) {
			// Compact into a fresh buffer, keeping only unconsumed bytes.
			final grown = Bytes.alloc(Std.int(Math.max(READ_CHUNK_SIZE, (unread + count) * 2)));
			grown.blit(0, rx, rxStart, unread);
			rx = grown;
			rxStart = 0;
			rxEnd = unread;
		}
		rx.blit(rxEnd, src, 0, count);
		rxEnd += count;
	}

	inline function readUInt32(at:Int):Int {
		return (rx.get(at) << 24) | (rx.get(at + 1) << 16) | (rx.get(at + 2) << 8) | rx.get(at + 3);
	}

	function parseFrames(s:Socket):Void {
		while (readyState != Closed) {
			final available = rxEnd - rxStart;
			if (available < 2)
				return;

			final b0 = rx.get(rxStart);
			final b1 = rx.get(rxStart + 1);
			final fin = (b0 & 0x80) != 0;
			final rsv = (b0 >> 4) & 0x07;
			final opcode = b0 & 0x0F;
			final masked = (b1 & 0x80) != 0;
			var payloadLen = b1 & 0x7F;
			var headerLen = 2;

			if (payloadLen == 126) {
				if (available < 4)
					return;
				payloadLen = (rx.get(rxStart + 2) << 8) | rx.get(rxStart + 3);
				headerLen = 4;
				if (payloadLen <= 125) {
					fail(s, StatusCode.ProtocolError, "non-minimal length encoding");
					return;
				}
			} else if (payloadLen == 127) {
				if (available < 10)
					return;
				final hi = readUInt32(rxStart + 2);
				final lo = readUInt32(rxStart + 6);
				// Reject anything that doesn't fit in our limit, including a set MSB (lo < 0).
				if (hi != 0 || lo < 0 || lo > Configuration.WebSocketMaxPayloadSize) {
					fail(s, StatusCode.MessageTooBig, "payload too large");
					return;
				}
				payloadLen = lo;
				headerLen = 10;
				if (payloadLen <= 0xFFFF) {
					fail(s, StatusCode.ProtocolError, "non-minimal length encoding");
					return;
				}
			}

			if (!masked) {
				fail(s, StatusCode.ProtocolError, "client frames must be masked");
				return;
			}
			if (rsv != 0) {
				fail(s, StatusCode.ProtocolError, "reserved bits set");
				return;
			}
			if (opcode >= 8 && (!fin || payloadLen > 125)) {
				fail(s, StatusCode.ProtocolError, "invalid control frame");
				return;
			}
			if (!isKnownOpcode(opcode)) {
				fail(s, StatusCode.ProtocolError, "unknown opcode " + opcode);
				return;
			}
			if (payloadLen > Configuration.WebSocketMaxPayloadSize) {
				fail(s, StatusCode.MessageTooBig, "payload too large");
				return;
			}

			final frameSize = headerLen + 4 + payloadLen;
			if (available < frameSize)
				return; // wait for the rest of the frame

			final maskAt = rxStart + headerLen;
			final dataAt = maskAt + 4;
			final payload = Bytes.alloc(payloadLen);
			for (i in 0...payloadLen)
				payload.set(i, rx.get(dataAt + i) ^ rx.get(maskAt + (i & 3)));

			rxStart += frameSize;
			if (rxStart == rxEnd) {
				rxStart = 0;
				rxEnd = 0;
			}

			handleFrame(s, fin, opcode, payload);
		}
	}

	function handleFrame(s:Socket, fin:Bool, opcode:Int, payload:Bytes):Void {
		// After we've sent Close, the only frame that still matters is the peer's Close.
		if (closeSent && opcode != OpCode.Close)
			return;

		switch (opcode) {
			case OpCode.Close:
				handleClose(s, payload);
			case OpCode.Ping:
				if (!writeFrame(s, true, OpCode.Pong, payload))
					finish(s, StatusCode.AbnormalClosure, "write failed");
			case OpCode.Pong:
				{}
			default:
				handleDataFrame(s, fin, opcode, payload);
		}
	}

	function handleDataFrame(s:Socket, fin:Bool, opcode:Int, payload:Bytes):Void {
		var buffer = fragmentBuffer;
		if (opcode == OpCode.Continuation) {
			if (buffer == null) {
				fail(s, StatusCode.ProtocolError, "unexpected continuation frame");
				return;
			}
		} else {
			if (buffer != null) {
				fail(s, StatusCode.ProtocolError, "new data frame before the previous message finished");
				return;
			}
			fragmentOpcode = opcode;
			buffer = fragmentBuffer = new BytesBuffer();
			fragmentSize = 0;
		}

		if (fragmentSize + payload.length > Configuration.WebSocketMaxPayloadSize) {
			fail(s, StatusCode.MessageTooBig, "message too large");
			return;
		}
		buffer.add(payload);
		fragmentSize += payload.length;

		if (!fin)
			return;

		final message = buffer.getBytes();
		final messageOpcode = fragmentOpcode;
		fragmentBuffer = null;
		fragmentOpcode = -1;
		fragmentSize = 0;

		if (messageOpcode == OpCode.Text) {
			if (!isValidUtf8(message)) {
				fail(s, StatusCode.InvalidPayloadData, "invalid UTF-8 in text message");
				return;
			}
			pending.push(TextMessage(message.toString()));
		} else {
			pending.push(BytesMessage(message));
		}
	}

	function handleClose(s:Socket, payload:Bytes):Void {
		var code = StatusCode.NoStatusReceived;
		var reason = "";

		if (payload.length == 1) {
			fail(s, StatusCode.ProtocolError, "malformed close payload");
			return;
		}
		if (payload.length >= 2) {
			code = (payload.get(0) << 8) | payload.get(1);
			if (!isValidCloseCode(code)) {
				fail(s, StatusCode.ProtocolError, "invalid close code " + code);
				return;
			}
			if (payload.length > 2) {
				final rawReason = payload.sub(2, payload.length - 2);
				if (!isValidUtf8(rawReason)) {
					fail(s, StatusCode.InvalidPayloadData, "invalid UTF-8 in close reason");
					return;
				}
				reason = rawReason.toString();
			}
		}

		if (!closeSent)
			sendClose(s, code, null);
		finish(s, code, reason);
	}

	function sendClose(s:Socket, code:Int, reason:Null<String>):Void {
		closeSent = true;
		readyState = Closing;
		closeDeadline = Timer.stamp() + WS_CLOSE_TIMEOUT;

		final body = new BytesBuffer();
		if (code != StatusCode.NoStatusReceived) {
			body.addByte((code >> 8) & 0xFF);
			body.addByte(code & 0xFF);
			if (reason != null) {
				final bytes = Bytes.ofString(reason);
				var len = bytes.length;
				if (len > 123) {
					len = 123;
					while (len > 0 && (bytes.get(len) & 0xC0) == 0x80)
						len--;
				}
				body.addBytes(bytes, 0, len);
			}
		}
		writeFrame(s, true, OpCode.Close, body.getBytes());
	}

	function fail(s:Socket, code:Int, message:String):Void {
		if (!closeSent)
			sendClose(s, code, message);
		finish(s, code, message);
	}

	function finish(s:Socket, code:Int, reason:String):Void {
		if (readyState == Closed)
			return;
		readyState = Closed;
		pending.push(CloseEvent({code: code, reason: reason}));
		try {
			s.close();
		} catch (_:Dynamic) {}
	}

	function writeFrame(s:Socket, fin:Bool, opcode:Int, payload:Bytes):Bool {
		try {
			final out = s.output;
			final len = payload.length;
			out.bigEndian = true;
			out.writeByte((fin ? 0x80 : 0) | opcode);
			if (len <= 125) {
				out.writeByte(len);
			} else if (len <= 0xFFFF) {
				out.writeByte(126);
				out.writeUInt16(len);
			} else {
				out.writeByte(127);
				out.writeInt32(0);
				out.writeInt32(len);
			}
			out.write(payload);
			out.flush();
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	static function isKnownOpcode(op:Int):Bool {
		return op == OpCode.Continuation || op == OpCode.Text || op == OpCode.Binary || (op >= OpCode.Close && op <= OpCode.Pong);
	}

	static function isValidCloseCode(code:Int):Bool {
		return (code >= 1000 && code <= 1003) || (code >= 1007 && code <= 1014) || (code >= 3000 && code <= 4999);
	}

	static function isValidUtf8(b:Bytes):Bool {
		var i = 0;
		final n = b.length;
		while (i < n) {
			final c = b.get(i);
			if (c < 0x80) {
				i++;
				continue;
			}
			var extra:Int;
			if (c >= 0xC2 && c <= 0xDF)
				extra = 1;
			else if (c >= 0xE0 && c <= 0xEF)
				extra = 2;
			else if (c >= 0xF0 && c <= 0xF4)
				extra = 3;
			else
				return false;

			if (i + extra >= n)
				return false;

			final second = b.get(i + 1);
			if (c == 0xE0 && second < 0xA0)
				return false;
			if (c == 0xED && second > 0x9F)
				return false;
			if (c == 0xF0 && second < 0x90)
				return false;
			if (c == 0xF4 && second > 0x8F)
				return false;

			for (k in 1...extra + 1)
				if ((b.get(i + k) & 0xC0) != 0x80)
					return false;
			i += extra + 1;
		}
		return true;
	}
}

class WebSocketException extends Exception {}
