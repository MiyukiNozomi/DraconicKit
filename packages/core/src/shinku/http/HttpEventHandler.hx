package shinku.http;

import haxe.Timer;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.Error;
import shinku.Console.Logger;
import shinku.http.HttpMessages.HttpRequest;
import shinku.http.HttpMessages.HttpResponse;
import shinku.net.NetworkEventHandler;

class HttpEventHandler extends NetworkEventHandler {
	public static final MAXIMUM_PAYLOAD_LENGTH = 8 * 1024 * 1024; // 8 MiB.

	public static final MAX_CRLF_LINE_LENGTH = 64 * 1024;

	public static final MAX_CHUNKED_TRANSFER_BLOCK_SIZE = 4 * 1024 * 1024; // 4 MiB

	public static final SOCKET_TIMEOUT_SECONDS = 10;

	public static final READ_UNTIL_CRLF_TIMEOUT = 10; // 10 Seconds max for a CRLF line read.

	public static final MAX_HEADER_BYTES = 32 * 1024;

	public static final ACCEPTED_METHODS = ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS"];

	public static final DISALLOWED_DUPLICATE_HEADERS = ["host", "content-length", "transfer-encoding"];

	var httpServer:HttpServer;

	public function new(socket, httpServer) {
		super(socket);
		this.httpServer = httpServer;
	}

	public function handleEvent() {
		try {
			final request = this.parseAndGetRequest();
			HttpResponseHandler.handleRequest(request, this, this.httpServer);
		} catch (err:HttpResponse) {
			HttpResponseHandler.writeResponse(err, this);
			this.requestClose();
		}
	}

	private function parseAndGetRequest() {
		var request = this.buildRequestHead();
		if (request == null)
			return null;

		// HTTP 1.1 mandates the existence of Host.
		var host = request.getHeader("host");
		if (host == null || StringTools.trim(host).length == 0)
			throw new HttpResponse(400);

		var hasTransferEncoding = request.headers.exists("transfer-encoding");
		var hasContentLength = request.headers.exists("content-length");
		if (hasTransferEncoding && hasContentLength)
			throw new HttpResponse(400);

		if (hasTransferEncoding) {
			return this.readBodyAsChunkedEncoding(request);
		} else if (hasContentLength) {
			return this.readBodyFromContentLength(request);
		} else {
			return request;
		}
	}

	private function readBodyAsChunkedEncoding(request:HttpRequest) {
		var header = request.getHeader("transfer-encoding", "")
			.split(",")
			.map(StringTools.trim)
			.filter(v -> v.length > 0);

		if (!(header.length == 1 && header[0].toLowerCase() == "chunked")) {
			throw new HttpResponse(400);
		}
		request.payload = new HttpChunkedInput(this);
		return request;
	}

	private function readBodyFromContentLength(request:HttpRequest) {
		final contentLengthHeader = request.getHeader("content-length");
		if (contentLengthHeader == null)
			throw Error.Custom("readBodyFromContentLength called without a content-length header.");

		if (!(~/^[0-9]+$/).match(contentLengthHeader))
			throw new HttpResponse(400, ["content-type" => ["text/plain"]], Bytes.ofString("Bad Content-Length"));

		var amount = Std.parseInt(contentLengthHeader);

		if (amount == null || amount < 0)
			throw new HttpResponse(400, ["content-type" => ["text/plain"]], Bytes.ofString("Bad Content-Length"));

		if (amount > MAXIMUM_PAYLOAD_LENGTH)
			throw new HttpResponse(413);

		var contentBytes = Bytes.alloc(amount);
		socket.input.readFullBytes(contentBytes, 0, amount);

		request.payload = new BytesInput(contentBytes);
		return request;
	}

	private function buildRequestHead() {
		var requestBuffer = this.readUntilCRLF();

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
		if (!ACCEPTED_METHODS.contains(method))
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

	public function readUntilCRLF(customTimeoutSeconds = READ_UNTIL_CRLF_TIMEOUT):Bytes {
		try {
			var bytes = new BytesBuffer();
			var prev = 0;

			var start = Timer.stamp();

			while (true) {
				// what the heck? another timeout??
				/*
					Here's why: the socket timeout is used BETWEEN bytes, not for the entire operation.
					this timeout only applies to the entire CRLF operation, otherwise an attacker can hang until we reach the limit for 10 seconds between each byte
				 */
				if (Timer.stamp() - start > customTimeoutSeconds) {
					throw Error.Custom("Took longer than " + customTimeoutSeconds + " seconds to fully read a CRLF-terminated line.");
				}
				var next = socket.input.readByte();
				socket.setTimeout(SOCKET_TIMEOUT_SECONDS);

				if (bytes.length >= MAX_CRLF_LINE_LENGTH) {
					Logger.debug("Warning: Hit CRLF-terminated line maximum limit of " + MAX_CRLF_LINE_LENGTH);
					throw new HttpResponse(400, ["content-type" => ["text/plain"]],
						Bytes.ofString("CRLF Line too long (limit " + MAX_CRLF_LINE_LENGTH + " yours: " + bytes.length + ")"));
				}

				bytes.addByte(next);

				if (prev == '\r'.charCodeAt(0) && next == '\n'.charCodeAt(0)) {
					var bs = bytes.getBytes();
					return bs.sub(0, bs.length - 2);
				}

				prev = next;
			}
		} catch (err:HttpResponse) {
			throw err;
		} catch (err:Dynamic) {
			Logger.debug(err);
			throw err;
		}
	}
}
