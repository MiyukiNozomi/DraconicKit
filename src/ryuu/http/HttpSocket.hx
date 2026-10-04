package ryuu.http;

import haxe.io.Input;
import haxe.io.Encoding;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.Error;
import ryuu.http.HttpMessages.HttpRequest;
import ryuu.http.HttpMessages.HttpResponse;
import sys.net.Socket;

// Should probably be called a Http11Socket.. but alright.
class HttpSocket {
	public var socket(default, null):Socket;

	// TODO: make this configurable?
	// TODO: also use this (after making it configurable) on Http11ChunkedInput.
	public static final MAXIMUM_PAYLOAD_LENGTH = 8 * 1024 * 1024; // 8 MiB.

	public static final MAX_CRLF_LINE_LENGTH = 64 * 1024;

	public static final READ_UNTIL_CRLF_TIMEOUT = 10; // 10 Seconds max for a CRLF line read.

	public static final MAX_HEADER_BYTES = 32 * 1024;

	public static final ACCEPTED_HEADERS = ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS"];

	public static final DISALLOWED_DUPLICATE_HEADERS = ["content-length", "transfer-encoding"];

	public function new(socket:Socket) {
		socket.setTimeout(10);
		this.socket = socket;
	}

	private function isAcceptedMethod(methodStr:String) {
		return ACCEPTED_HEADERS.contains(methodStr);
	}

	public function nextRequest():Null<HttpRequest> {
		var request = this.buildRequestHead();
		if (request == null)
			return null;

		// HTTP 1.1 mandates the existance of Host.
		if (!request.headers.exists("host")) {
			throw new HttpResponse(400);
		}

		var hasTransferEncoding = request.headers.exists("transfer-encoding");
		var hasContentLength = request.headers.exists("content-length");

		if (hasTransferEncoding && hasContentLength)
			throw new HttpResponse(400);

		// TODO: compression for the buffer based one too..
		if (hasTransferEncoding) {
			return this.readBodyAsChunkedEncoding(request);
		} else if (hasContentLength) {
			return this.readBodyFromContentLength(request);
		}

		return request;
	}

	public function sendResponse(response:HttpResponse) {
		response.prepareBeforeCommit();

		// prepare yourselves, this is going to be annoying as hell!
		var requestHead = ['HTTP/1.1 ${response.status} ${response.statusText()}'];
		for (key => value in response.headers) {
			requestHead.push('${key}: ${value}');
		}
		requestHead.push("");
		requestHead.push("");
		// push two empty lines so we always end with CRLF.

		// this is probably wrong, but lets see.
		this.socket.output.writeString(requestHead.join("\r\n"), Encoding.UTF8);
		this.socket.output.flush();

		if (response.payload != null) {
			var buffer = Std.downcast(response.payload, Bytes);
			var stream = Std.downcast(response.payload, Input);

			if (buffer != null) {
				this.socket.output.write(buffer);
				this.socket.output.flush();
			} else if (stream != null) {
				try {
					var nRead = 4096;
					var buff = Bytes.alloc(nRead);
					while (nRead == buff.length) {
						nRead = stream.readBytes(buff, 0, buff.length);
						if (nRead > 0) {
							this.socket.output.writeString('${StringTools.hex(nRead)}\r\n');
							this.socket.output.writeBytes(buff, 0, nRead);
							this.socket.output.writeString('\r\n');
							this.socket.output.flush();
						}
					}
				} catch (eof:haxe.io.Eof) {}
				this.socket.output.writeString("0\r\n\r\n");
				this.socket.output.flush();
				stream.close();
			}
		}
	}

	private function buildRequestHead() {
		// bad request!
		var requestBuffer = this.readUntilCRLF();
		if (requestBuffer == null)
			return null;

		// Parse status line..
		// Yes, we are accepting multiple spaces here, but that's just in case.
		var requestLine = requestBuffer.toString().split(" ").filter(v -> v.length > 0);
		if (requestLine.length != 3)
			throw new HttpResponse(400);

		var method = requestLine[0];
		var target = requestLine[1];
		var version = requestLine[2];

		if (version != "HTTP/1.1")
			throw new HttpResponse(400);
		if (!isAcceptedMethod(method))
			throw new HttpResponse(405);

		var request = new HttpRequest({method: method, target: target, version: version}, new Map());

		var lineBuffer;
		var totalBufferSize = 0;

		while ((lineBuffer = this.readUntilCRLF()) != null && lineBuffer.length > 0) {
			totalBufferSize += lineBuffer.length;
			if (totalBufferSize > MAX_HEADER_BYTES) {
				throw new HttpResponse(431);
			}

			var lineStr = lineBuffer.toString();
			var separator = lineStr.indexOf(":");
			if (separator == -1)
				throw new HttpResponse(400);
			var key = lineStr.substring(0, separator).toLowerCase();
			if (key.length == 0 || !~/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.match(key))
				throw new HttpResponse(400);
			var value = StringTools.trim(lineStr.substring(separator + 1));

			if (DISALLOWED_DUPLICATE_HEADERS.contains(key) && request.headers.exists(key)) {
				throw new HttpResponse(400);
			}

			var narray = request.headers.get(key);
			var array = narray == null ? [] : narray;
			array.push(value);
			request.headers.set(key, array);
		}

		return request;
	}

	private function readBodyAsChunkedEncoding(request:HttpRequest) {
		var header = request.getHeader("transfer-encoding", "")
			.split(",")
			.map(StringTools.trim)
			.filter(v -> v.length > 0);

		// TODO: compression
		if (!header.contains("chunked")) {
			throw new HttpResponse(400);
		}
		request.payload = new Http11ChunkedInput(this);
		return request;
	}

	private function readBodyFromContentLength(request:HttpRequest) {
		final contentLengthHeader = request.getHeader("content-length");
		if (contentLengthHeader == null)
			throw Error.Custom("readBodyFromContentLength called without a content-length header.");

		var amount = Std.parseInt(contentLengthHeader);
		if (amount == null || !(~/^[0-9]+$/).match(contentLengthHeader))
			throw new HttpResponse(400, {"content-type": "text/plain"}, Bytes.ofString("Bad Content-Length"));

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
			var bytes = new BytesBuffer();
			var prev = 0;

			var start = Sys.time();

			while (true) {
				// what the fuck? another timeout??
				/*
					Here's why: the socket timeout is used BETWEEN bytes, not for the entire operation.
					this timeout only applies to the entire CRLF operation, otherwise an attacker can hang until we reach the limit for 10 seconds between each byte
				 */
				if (Sys.time() - start > READ_UNTIL_CRLF_TIMEOUT) {
					throw Error.Custom("Took longer than " + READ_UNTIL_CRLF_TIMEOUT + " seconds to fully read a CRLF-terminated line.");
				}
				var next = socket.input.readByte();

				if (bytes.length + 1 >= MAX_CRLF_LINE_LENGTH) {
					trace("Warning: Hit CRLF-terminated line maximum limit of " + MAX_CRLF_LINE_LENGTH);
					throw new HttpResponse(400, {"content-type": "text/html"},
						Bytes.ofString("CRLF Line too long (limit " + MAX_CRLF_LINE_LENGTH + " yours: " + bytes.length + ")"));
				}

				bytes.addByte(next);

				if (prev == '\r'.charCodeAt(0) && next == '\n'.charCodeAt(0)) {
					var bs = bytes.getBytes();
					return bs.sub(0, bs.length - 2);
				}

				prev = next;
			}
		} catch (err) {
			if (Std.isOfType(err, HttpResponse))
				throw err;
			trace("readUntilCRLF failed: ", err.toString());
			throw new HttpResponse(400, {"content-type": "text/html"}, Bytes.ofString("Bad CRLF Line."));
		}
	}
}
