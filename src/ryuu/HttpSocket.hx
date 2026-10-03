package ryuu;

import haxe.io.BytesInput;
import haxe.io.Bytes;
import ryuu.HttpMessages.HttpResponse;
import haxe.io.BytesBuffer;
import ryuu.HttpMessages.HttpRequest;
import sys.net.Socket;

class HttpSocket {
	public var socket(default, null):Socket;

	// TODO: make this configurable?
	final MAXIMUM_PAYLOAD_LENGTH = 8 * 1024 * 1024; // 8 MiB.

	public function new(socket:Socket) {
		socket.setTimeout(10);
		this.socket = socket;
	}

	private function isAcceptedMethod(methodStr:String) {
		return ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS"].contains(methodStr);
	}

	public function nextRequest():Null<HttpRequest> {
		var request = this.buildRequestHead();
		if (request == null)
			return null;

		// HTTP 1.1 mandates the existance of Host.
		if (!request.headers.exists("host")) {
			throw new HttpResponse(400);
		}

		// TODO: accept chunked transfer encoding onto that input stream?
		// TODO: enforce methods that can have contents

		if (request.headers.get("transfer-encoding") == "chunked") {
			return this.readBodyAsChunkedEncoding(request);
		} else if (request.headers.exists("content-length")) {
			return this.readBodyFromContentLength(request);
		}

		return request;
	}

	private function buildRequestHead() {
		// bad request!
		var requestBuffer = this.readUntilCRLF();
		if (requestBuffer == null)
			return null;

		// Parse status line..
		var requestLine = requestBuffer.toString().split(" ").filter(v -> v.length > 0);
		if (requestLine.length != 3)
			return null;

		var method = requestLine[0].toUpperCase();
		var target = requestLine[1];
		var version = requestLine[2];

		if (version != "HTTP/1.1" || !isAcceptedMethod(method))
			return null;

		var request = new HttpRequest({method: method, target: target, version: version}, new Map());

		var lineBuffer;

		while ((lineBuffer = this.readUntilCRLF()) != null && lineBuffer.length > 0) {
			var lineStr = lineBuffer.toString();
			var separator = lineStr.indexOf(":");
			if (separator == -1)
				return null;
			var key = StringTools.trim(lineStr.substring(0, separator)).toLowerCase();
			if (key.length == 0)
				return null;
			var value = StringTools.trim(lineStr.substring(separator + 1));
			request.headers.set(key, value);
		}

		return request;
	}

	private function readBodyAsChunkedEncoding(request:HttpRequest) {
		request.payload = new Http11ChunkedInput(this);
		return request;
	}

	private function readBodyFromContentLength(request:HttpRequest) {
		final contentLengthHeader = request.headers.get("content-length");
		if (contentLengthHeader == null)
			return null;

		var amount = Std.parseInt(contentLengthHeader);
		if (amount == null)
			return null;
		if (amount < 0 || amount > MAXIMUM_PAYLOAD_LENGTH)
			throw new HttpResponse(413);

		var contentBytes = Bytes.alloc(amount);
		var offset = 0;

		socket.input.readFullBytes(contentBytes, offset, amount - offset);

		request.payload = new BytesInput(contentBytes);
		return request;
	}

	public function readUntilCRLF() {
		try {
			final MAX_CRLF_LINE_LENGTH = 65553;

			var bytes = new BytesBuffer();
			var prev = 0;
			while (true) {
				var next = socket.input.readByte();
				bytes.addByte(next);

				if (bytes.length >= MAX_CRLF_LINE_LENGTH) {
					trace("Warning: Hit CRLF-terminated line maximum limit of " + MAX_CRLF_LINE_LENGTH);
					return null;
				}

				if (prev == '\r'.charCodeAt(0) && next == '\n'.charCodeAt(0)) {
					var bs = bytes.getBytes();
					return bs.sub(0, bs.length - 2);
				}

				prev = next;
			}
		} catch (err) {
			trace("readUntilCRLF failed: ", err.toString());
			return null;
		}
	}
}
