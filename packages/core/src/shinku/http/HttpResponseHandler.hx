package shinku.http;

import haxe.io.Encoding;
import haxe.io.Input;
import haxe.io.Bytes;
import shinku.Console.Logger;
import shinku.http.HttpMessages.HttpResponse;
import shinku.http.HttpMessages.HttpRequest;

class HttpResponseHandler {
	public static function handleRequest(req:Null<HttpRequest>, transport:HttpEventHandler, server:HttpServer) {
		if (req == null) {
			Logger.warn("Got a broken request!");
			transport.requestClose();
			return;
		}
		if (Configuration.ShowDevRequests)
			Logger.info(req.status);

		try {
			server.requestHandler.handleRequest(server, transport, req);
		} catch (res:HttpResponse) {
			res.sourceRequest = req;
			Logger.debug("Response for ", transport.peer, " is ", res.status);
			writeResponse(res, transport);

			if (res.forceSocketClosure || wantsConnectionClose(req)) {
				transport.requestClose();
				return;
			}

			try {
				if (res.onResponseWritten != null)
					res.onResponseWritten();
			} catch (e) {
				Logger.error("An exception was thrown inside of the onResponseWritten!\n" + e.toString() + "\n" + e.stack.toString());
			}

			// So, it's switching protocols, that means this thread cannot continue handling it.
			if (res.status == 101) {
				// Stop handling this socket, keep it open so the underlying transfer protocol can manage it.
				transport.requestDetatch();
			}
		} catch (err) {
			Logger.error(err.toString());
			Logger.error(err.stack.toString());
			transport.requestClose();
		}
	}

	public static function wantsConnectionClose(req:Null<HttpRequest>):Bool {
		if (req == null)
			return false;

		final chunked = Std.downcast(req.payload, HttpChunkedInput);
		if (chunked != null && !chunked.isFinished) {
			#if dev
			Logger.warn("Request for", req.status,
				"will be forcefully closed as the chunked transfer input stream was not fully consumed. (this warning will not appear in production.)");
			#end
			return true;
		}
		final connection = (req.getHeader("connection", "keep-alive") + "").toLowerCase();
		return connection.indexOf("close") != -1;
	}

	public static function writeResponse(response:HttpResponse, transport:HttpEventHandler) {
		try {
			response.prepareBeforeCommit();

			// prepare yourselves, this is going to be annoying as hell!
			var requestHead = ['HTTP/1.1 ${response.status} ${response.statusText()}'];
			for (key => value in response.headersIterator()) {
				for (v in value) {
					requestHead.push('${key}: ${v}');
				}
			}
			requestHead.push("");
			requestHead.push("");
			// push two empty lines so we always end with CRLF.

			// this is probably wrong, but lets see.
			transport.socket.output.writeString(requestHead.join("\r\n"), Encoding.UTF8);
			transport.socket.output.flush();

			var didOriginateFromHEAD = response.isBodyDisallowed();

			if (response.payload != null) {
				var buffer = Std.downcast(response.payload, Bytes);
				var stream = Std.downcast(response.payload, Input);

				if (buffer != null) {
					if (!didOriginateFromHEAD) {
						transport.socket.output.write(buffer);
						transport.socket.output.flush();
					}
				} else if (stream != null) {
					if (!didOriginateFromHEAD) {
						try {
							var nRead = 4096;
							var buff = Bytes.alloc(nRead);
							while (nRead == buff.length) {
								nRead = stream.readBytes(buff, 0, buff.length);
								if (nRead > 0) {
									transport.socket.output.writeString('${StringTools.hex(nRead)}\r\n');
									transport.socket.output.writeFullBytes(buff, 0, nRead);
									transport.socket.output.writeString('\r\n');
									transport.socket.output.flush();
								}
							}
						} catch (eof:haxe.io.Eof) {}
						transport.socket.output.writeString("0\r\n\r\n");
						transport.socket.output.flush();
					}
					transport.requestClose();
				}
			}
		} catch (err) {
			Logger.debug("Could not send response to " + transport.peer.host + "!");
			Logger.debug(err);
			transport.requestClose();
			final stream = response.payload != null ? Std.downcast(response.payload, Input) : null;
			if (stream != null) {
				stream.close();
			}
		}
	}
}
