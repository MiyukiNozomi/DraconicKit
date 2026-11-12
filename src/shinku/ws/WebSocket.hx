package shinku.ws;

import haxe.Exception;
import haxe.Int64;
import haxe.extern.EitherType;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Error;
import hx.concurrent.collection.Queue;
import shinku.Console.Logger;
import shinku.std.URL;
import shinku.std.threading.Synchronized;
import sys.net.Socket;

enum WebSocketReadyState {
	/** 
		this entry is only here for compliance, not for userfullness. 
		By the time you receive a WebSocket instance, the handshake will already have been completed.
	**/
	Connecting;

	Open;
	Closing;
	Closed;
}

typedef PartialFrame = {
	opcode:Int,
	payload:BytesBuffer
}

typedef ReadyFrame = {
	opcode:Int,
	?payload:Bytes
}

private class WebSocketOpCodes {
	// Non-first frame of a fragmented message.	Message fragmentation
	public static final ContinuationFrame = 0;
	// UTF-8-encoded text.
	public static final Text = 1;
	//	Binary data.
	public static final Binary = 2;

	// 3–7	Reserved for further non-control frames. May be defined by an extension.
	// close(), onclose	The WebSocket closing handshake starts upon either sending or receiving a Close frame.[64] It may prevent data loss by complementing the TCP closing handshake.[65] No frame can be sent after sending a Close frame. If a Close frame is received and no prior Close frame was sent, a Close frame must be sent in response (typically echoing the status code received). The payload is optional, but if present, it must start with a two-byte big-endian unsigned integer status code, optionally followed by a UTF-8-encoded reason message not longer than 123 bytes.
	public static final Close = 8;

	// May be used for latency measurement, keepalive and heartbeat. Both sides can send a ping (with any payload). Whoever receives it must, as soon as is practical, send back a pong with the same payload. A pong should be ignored if no prior ping was sent.[67][68][69]
	public static final Ping = 9;
	// Response.
	public static final Pong = 10;
	// 11–15		Reserved for further control frames. May be defined by an extension.[62
}

private class WebSocketStatusCodes {
	public static final NormalClosure = 1000;
	public static final GoingAway = 1001;
	public static final ProtocolError = 1002;
	public static final UnsupportedData = 1003;
	public static final NoCodeReceived = 1005;
	public static final AbnormalClose = 1006;
	public static final InvalidPayloadData = 1007;
	public static final PolicyViolated = 1008;
	public static final MessageTooBig = 1009;
	public static final UnsupportedExtension = 1010;
	public static final InternalServerError = 1011;
}

/***

	A server-oriented websocket implementation

	(after all.. it's a backend framework and not a frontend one..)

	List of TODOs: 
	 
	- Proper close handshake `our closing handshake is.. wonky `
	- `onError` event.

	@author suisei
**/
class WebSocket {
	// TODO: make these configurable?
	public static final WS_SOCKET_TIMEOUT = 1.0;
	// This other timeout is just so we know if we received something or not.
	public static final WS_SOCKET_POKE_TIMEOUT = 0.1;
	// 4 MiB
	public static final WS_MAX_PAYLOAD_SIZE = 4 * 1024 * 1024;

	private var socket:Synchronized<Socket>;

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
	public var readyState(default, null):WebSocketReadyState;

	/**
		The absolute URL of the WebSocket.
	**/
	public var url:URL;

	private var packetBackbuffer:Queue<ReadyFrame>;
	private var currentPacket:Null<PartialFrame>;

	private var haveWeWrittenACloseFrame = false;

	public var onTextMessage(never, set):Null<(msg:String) -> Void>;
	public var onBytesMessage(never, set):Null<(msg:Bytes) -> Void>;
	public var onClose(never, set):Null<(msg:{?code:Int, ?reason:String}) -> Void>;

	private var events:{
		onTextMessage:Synchronized<Null<(msg:String) -> Void>>,
		onBytesMessage:Synchronized<Null<(msg:Bytes) -> Void>>,
		onClose:Synchronized<Null<(msg:{?code:Int, ?reason:String}) -> Void>>,
	};

	function set_onTextMessage(value:Null<(msg:String) -> Void>):Null<(msg:String) -> Void> {
		events.onTextMessage.modify(_ -> return value);
		return value;
	}

	function set_onBytesMessage(value:Null<(msg:Bytes) -> Void>):Null<(msg:Bytes) -> Void> {
		events.onBytesMessage.modify(_ -> return value);
		return value;
	}

	function set_onClose(value:Null<(msg:{?code:Int, ?reason:String}) -> Void>):Null<(msg:{?code:Int, ?reason:String}) -> Void> {
		events.onClose.modify(_ -> return value);
		return value;
	}

	public function new(url:URL, socket:Socket, appProtocol:Null<String>) {
		this.socket = new Synchronized(socket);
		this.readyState = Open;
		this.protocol = appProtocol ?? "";
		this.url = url;
		this.socket.access(s -> s.setTimeout(WS_SOCKET_TIMEOUT));
		this.packetBackbuffer = new Queue();
		this.events = {
			onTextMessage: new Synchronized(null),
			onBytesMessage: new Synchronized(null),
			onClose: new Synchronized(null),
		}
	}

	public function send(data:EitherType<String, Bytes>) {
		var isString = Std.downcast(data, String) != null;
		var buff = Std.downcast(data, Bytes);
		if (buff == null) {
			buff = Bytes.ofString(cast(data, String));
		}
		if (this.readyState != Open) {
			throw new WebSocketException("readyState != Open");
		}
		this.socket.access(s -> {
			writeFrame(s, {
				fin: true,
				opcode: isString ? WebSocketOpCodes.Text : WebSocketOpCodes.Binary,
				payload: buff
			});
		});
	}

	public function close(code = WebSocketStatusCodes.NormalClosure, reason = null) {
		this.socket.access(s -> {
			writeCloseFrame(s, code, reason);
		});
	}

	/**
		# INTERNAL USAGE ONLY!
	**/
	@:internal public function hasReadyPackets() {
		return this.socket.access(s -> {
			var header;
			try {
				header = tryReadFrameHeader(s);
			} catch (e:Error) {
				switch (e) {
					case Custom(msg):
						writeCloseFrame(s, WebSocketStatusCodes.ProtocolError, msg);
					default:
				}
				throw e;
			}
			if (header == null)
				return false;
			var payload:Null<Bytes> = null;
			final payloadSize = Int64.toInt(header.payloadSize);
			if (payloadSize > 0) {
				if (payloadSize > WS_MAX_PAYLOAD_SIZE || payloadSize < 0) {
					writeCloseFrame(s, WebSocketStatusCodes.MessageTooBig);
					return false;
				}
				payload = Bytes.alloc(payloadSize);
				s.input.readFullBytes(payload, 0, payloadSize);
				for (i in 0...payload.length) {
					payload.set(i, payload.get(i) ^ header.maskingKey.get(i % 4));
				}
			}
			// we only do validation here, not processing.
			switch (header.opcode) {
				case WebSocketOpCodes.Text, WebSocketOpCodes.Binary: {
						if (currentPacket != null) {
							writeCloseFrame(s, WebSocketStatusCodes.ProtocolError, "Unexpected new data frame during fragmentation");
							return false;
						}
						var packet:PartialFrame = {
							opcode: header.opcode,
							payload: new BytesBuffer()
						};
						if (payload != null)
							packet.payload.add(payload);
						if (header.fin == 0)
							currentPacket = packet;
						else {
							if (header.opcode == WebSocketOpCodes.Text) {
								try {
									packet.payload.getBytes().toString();
								} catch (_) {
									writeCloseFrame(s, WebSocketStatusCodes.ProtocolError, "Expected a UTF-8 string for a Text payload.");
									return false;
								}
							}
							packetBackbuffer.push({
								opcode: packet.opcode,
								payload: packet.payload.getBytes()
							});
						}
					}
				case WebSocketOpCodes.ContinuationFrame:
					var packet:PartialFrame;
					if (currentPacket == null) {
						writeCloseFrame(s, WebSocketStatusCodes.ProtocolError, "Unexpected continuation frame");
						return false;
					} else {
						packet = currentPacket;
					}
					if (payload != null) {
						final totalSize = packet.payload.length + payload.length;
						if (totalSize > WS_MAX_PAYLOAD_SIZE || totalSize < 0) {
							writeCloseFrame(s, WebSocketStatusCodes.MessageTooBig);
							return false;
						}
						packet.payload.add(payload);
					}
					if (header.fin == 1) {
						packetBackbuffer.push({
							opcode: packet.opcode,
							payload: packet.payload.getBytes()
						});
						currentPacket = null;
					}
				case WebSocketOpCodes.Close:
					this.packetBackbuffer.push({
						opcode: header.opcode,
						payload: payload
					});
				case WebSocketOpCodes.Ping, WebSocketOpCodes.Pong:
					this.packetBackbuffer.push({
						opcode: header.opcode,
						payload: payload
					});
					if (header.fin != 1) {
						writeCloseFrame(s, WebSocketStatusCodes.PolicyViolated, "Control frames are unfragmentable!");
						return false;
					}
				default: writeCloseFrame(s, WebSocketStatusCodes.ProtocolError, "Invalid / improperly negotiated opcode: " + header.opcode);
			}
			return true;
		});
	}

	/**
		# INTERNAL USAGE ONLY!
	**/
	@:internal public function fireEvents() {
		return this.socket.access(s -> {
			var amountToRead = this.packetBackbuffer.length;
			while (amountToRead > 0) {
				amountToRead--;
				var pack = this.packetBackbuffer.pop();
				if (pack == null)
					continue;
				switch (pack.opcode) {
					case WebSocketOpCodes.Close: {
							// TODO: read status and message from the client?
							var code = WebSocketStatusCodes.NormalClosure;
							var message = "";

							if (!this.haveWeWrittenACloseFrame) {
								writeFrame(s, {
									fin: true,
									opcode: WebSocketOpCodes.Close,
									payload: pack.payload
								});
								this.readyState = Closing;
							} else {
								this.readyState = Closed;
								s.close();
							}

							this.events.onClose.access(fn -> {
								if (fn != null)
									fn({code: code, reason: message});
							});
						}
					case WebSocketOpCodes.Text:
						{
							this.events.onTextMessage.access(fn -> {
								if (fn != null && pack.payload != null)
									fn(pack.payload.toString());
							});
						}
					case WebSocketOpCodes.Binary:
						{
							this.events.onBytesMessage.access(fn -> {
								if (fn != null && pack.payload != null)
									fn(pack.payload);
							});
						}
					case WebSocketOpCodes.Ping:
						writeFrame(s, {fin: true, opcode: WebSocketOpCodes.Pong, payload: pack.payload != null ? pack.payload : null});
					case WebSocketOpCodes.Pong: {
							// we have no operation to do with this.. for now i think?
						}
					default:
				}
			}
		});
	}

	private inline function writeCloseFrame(socket:Socket, statusCode:Int, ?reason:String) {
		if (!this.haveWeWrittenACloseFrame) {
			this.haveWeWrittenACloseFrame = true;
			var b = new BytesBuffer();
			b.addByte((statusCode >> 8) & 0xFF);
			b.addByte(statusCode & 0xFF);
			if (reason != null) {
				var reasonBytes = Bytes.ofString(reason);
				var maxLen = 125 - 2;
				b.addBytes(reasonBytes, 0, reasonBytes.length > maxLen ? maxLen : reasonBytes.length);
			}
			writeFrame(socket, {
				fin: true,
				opcode: WebSocketOpCodes.Close,
				payload: b.getBytes()
			});
			this.readyState = Closing;
		}
	}

	private function writeFrame(socket:Socket, data:{
		fin:Bool,
		opcode:Int,
		?payload:Bytes
	}) {
		final out = socket.output;
		out.bigEndian = true;
		final length = data.payload != null ? data.payload.length : 0;
		out.writeByte(((data.fin ? 1 : 0) << 7) | (data.opcode & 0x0F));
		if (length <= 125) {
			out.writeByte(length);
		} else if (length <= 0xFFFF) {
			out.writeByte(126);
			out.writeUInt16(length);
		} else {
			out.writeByte(127);
			out.writeInt32(0); // high 32 bits
			out.writeInt32(length); // low 32 bits
		}
		if (data.payload != null)
			out.write(data.payload);
		out.flush();
	}

	private function tryReadFrameHeader(socket:Socket):Null<{
		fin:Int,
		opcode:Int,
		payloadSize:Int64,
		maskingKey:Bytes
	}> {
		var headBytes:Bytes;
		try {
			socket.setTimeout(WS_SOCKET_POKE_TIMEOUT);
			// haxe's read implementation will only exit this function properly if all bytes i want are read.
			// otherwise? it explodes.
			headBytes = socket.input.read(2);
		} catch (_) {
			socket.setTimeout(WS_SOCKET_TIMEOUT);
			return null;
		}
		socket.setTimeout(WS_SOCKET_TIMEOUT);
		final byte0 = headBytes.get(0);
		final byte1 = headBytes.get(1);
		var fin:Int = byte0 >> 7,
			opcode:Int = byte0 & 0b1111,
			masked:Int = byte1 >> 7;
		if (masked != 1) {
			throw Error.Custom("The client must mask all frames!");
		}
		if (fin != 1 && opcode >= 8) {
			throw Error.Custom("Control frames are unfragmentable!");
		}
		final rsv = (byte0 >> 4) & 0b111;
		if (rsv != 0) {
			throw Error.Custom("Unexpected reserved bits");
		}
		var payloadSize:Int64 = Int64.ofInt(byte1 & 0x7F);
		if (payloadSize == Int64.ofInt(126)) {
			var bytes = socket.input.read(2);
			payloadSize = Int64.ofInt((bytes.get(0) << 8) | bytes.get(1));
			if (Int64.compare(payloadSize, Int64.ofInt(125)) <= 0) {
				throw Error.Custom("The minimum number of bits must be used");
			}
		} else if (payloadSize == Int64.ofInt(127)) {
			var bytes = socket.input.read(8);
			var high = bytes.getInt32(0);
			var low = bytes.getInt32(4);
			if (high < 0) {
				throw Error.Custom("The most significant bit must be zero");
			}
			payloadSize = Int64.make(high, low);
			if (Int64.compare(payloadSize, Int64.ofInt(65535)) <= 0) {
				throw Error.Custom("The minimum number of bits must be used");
			}
		}
		if (opcode >= 8 && payloadSize > Int64.ofInt(125)) {
			throw Error.Custom("Control frame payload exceeds 125 bytes");
		}
		final maskingKey = socket.input.read(4);
		return {
			fin: fin,
			maskingKey: maskingKey,
			payloadSize: payloadSize,
			opcode: opcode
		};
	}
}

class WebSocketException extends Exception {}
