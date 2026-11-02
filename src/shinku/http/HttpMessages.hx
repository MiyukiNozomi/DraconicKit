package shinku.http;

import haxe.io.Error;
import haxe.extern.EitherType;
import haxe.io.Bytes;
import haxe.Exception;
import haxe.Json;
import haxe.io.Input;

/**
	The request line of an HTTP request (e.g. `GET / HTTP/1.1`),
	split into its three components.
**/
typedef HttpRequestStatus = {
	method:String,
	target:String,
	version:String
}

/**
	Represents an incoming HTTP request.

	Header names are stored in lowercase. Also, headers are stored in an array of values.
**/
class HttpRequest {
	public var status:HttpRequestStatus;
	public var headers:Map<String, Array<String>>;

	/**
		The request body as a readable stream, or `null` if the request has no
		body
	**/
	public var payload:Null<Input>;

	public function new(status:HttpRequestStatus, headers:Map<String, Array<String>>) {
		this.status = status;
		this.headers = headers;
	}

	/**
		Checks whether the request contains the given header.

		The lookup is case-insensitive with respect to `key`.

		@param key The header name to look for (will be lowercased).
		@return `true` if the header is present, otherwise `false`.
	**/
	public function hasHeader(key:String) {
		return this.headers.exists(key.toLowerCase());
	}

	/**
		Gets the value of a header.

		The lookup is case-insensitive with respect to `key`. If the header was
		sent multiple times, the values are joined with `", "`.

		@param key The header name to look up.
		@param df The default value returned when the header is absent.
		@return The joined header value, or `df` if the header does not exist.
	**/
	public function getHeader(key:String, df:String = null) {
		var val = this.headers.get(key.toLowerCase());
		if (val == null)
			return df;
		return val.join(", ");
	}

	/**
		Returns a debug representation of the request: the request line as JSON,
		followed by a newline and the headers map. (payload not included)
	**/
	public function toString() {
		return Json.stringify(status) + "\n" + headers.toString();
	}
}

/**
	Represents an outgoing HTTP response.

	Extends `Exception` so a response can be thrown from anywhere in request
	handling (e.g. to short-circuit) and caught by the server,
	which then sends it to the client.

	Headers that describe the message framing (`server`, `content-length`,
	`transfer-encoding`) are managed automatically and cannot be set by the
	caller. See `prepareBeforeCommit`.
**/
class HttpResponse extends Exception {
	/**
		The request this response answers, if known. Used to apply
		request-dependent rules, such as omitting the body for `HEAD` requests.
	**/
	public var sourceRequest:Null<HttpRequest> = null;

	public var status(default, null):Int;
	public var headers(default, null):Map<String, String>;

	/**
		The response body, either as an in-memory `Bytes` buffer (sent with a
		`Content-Length`) or as an `Input` stream (sent with chunked transfer
		encoding). `null` means no body.
	**/
	public var payload(default, null):Null<EitherType<Input, Bytes>>;

	/**
		Creates a new response.

		Header names are lowercased and values are converted to strings.

		@param status The HTTP status code.
		@param headers Initial headers. Must not contain `server`,
			`content-length` or `transfer-encoding` (any casing).
		@param payload The response body, or `null` for no body.
		@throws haxe.io.Error.Custom If a disallowed header is supplied.
	**/
	public function new(status:Int, headers:Map<String, String> = [], payload:Null<EitherType<Input, Bytes>> = null) {
		super("HttpResponse");
		this.status = status;
		this.headers = new Map<String, String>();

		final DisallowedInputHeaders = ["server", "content-length", "transfer-encoding"];
		for (key => value in headers) {
			if (DisallowedInputHeaders.contains(key.toLowerCase())) {
				throw Error.Custom("Hey buddy, this header: " + key + " is not allowed to be manually set.");
			}
			this.headers.set(key.toLowerCase(), headers[key] + "");
		}

		this.payload = payload;
	}

	/**
		Determines whether this response must not include a message body.

		A body is disallowed for informational (`1xx`) responses, `204 No
		Content`, `304 Not Modified`, and any response to a `HEAD` request.

		@return `true` if no body may be sent, otherwise `false`.
	**/
	public function isBodyDisallowed() {
		if ((this.status >= 100 && this.status < 200) || status == 204 || status == 304)
			return true;
		return (this.sourceRequest != null && this.sourceRequest.status.method == "HEAD");
	}

	/**
		# INTERNAL USAGE ONLY!

		Thou shall not call this!
	**/
	public function prepareBeforeCommit() {
		var weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
		var months = [
			"Jan", "Feb", "Mar", "Apr", "May", "Jun",
			"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
		];

		function pad2(n:Int):String {
			return n < 10 ? "0" + n : Std.string(n);
		}

		var date = Date.now();
		headers.set("date",
			weekdays[date.getUTCDay()]
			+ ", "
			+ pad2(date.getUTCDate())
			+ " "
			+ months[date.getUTCMonth()]
			+ " "
			+ date.getUTCFullYear()
			+ " "
			+ pad2(date.getUTCHours())
			+ ":"
			+ pad2(date.getUTCMinutes())
			+ ":"
			+ pad2(date.getUTCSeconds())
			+ " GMT");

		headers.set("server", "Moonlit Crimson Dragon");

		var isHead = (this.sourceRequest != null && this.sourceRequest.status.method == "HEAD");

		if (this.payload != null) {
			if (!isHead && this.isBodyDisallowed())
				return;

			var buffer = Std.downcast(this.payload, Bytes);
			var stream = Std.downcast(this.payload, Input);

			if (buffer != null) {
				headers.set("content-length", buffer.length + "");
			} else if (stream != null) {
				headers.set("transfer-encoding", "chunked");
			}
		} else if (!this.isBodyDisallowed()) {
			headers.set("content-length", "0");
		}
	}

	/**
		Returns the standard reason phrase for this response's status code
		(e.g. `404` -> `"Not Found"`), for use in the status line.

		Covers the registered `1xx`-`5xx` codes. Unrecognized codes return an easter egg.

		(there are more hidden easter eggs)
	**/
	public function statusText():String {
		return switch (this.status) {
			case 100: "Continue";
			case 101: "Switching Protocols";
			case 102: "Processing";
			case 103: "Early Hints";

			case 200: "OK";
			case 201: "Created";
			case 202: "Accepted";
			case 203: "Non-Authoritative Information";
			case 204: "No Content";
			case 205: "Reset Content";
			case 206: "Partial Content";
			case 207: "Multi-Status";
			case 208: "Already Reported";
			case 226: "IM Used";

			case 300: "Multiple Choices";
			case 301: "Moved Permanently";
			case 302: "Found";
			case 303: "See Other";
			case 304: "Not Modified";
			case 305: "Use Proxy";
			case 307: "Temporary Redirect";
			case 308: "Permanent Redirect";

			case 400: "Bad Request";
			case 401: "Unauthorized";
			case 402: "Payment Required";
			case 403: "Forbidden";
			case 404: "Not Found";
			case 405: "Method Not Allowed";
			case 406: "Not Acceptable";
			case 407: "Proxy Authentication Required";
			case 408: "Request Timeout";
			case 409: "Conflict";
			case 410: "Gone";
			case 411: "Length Required";
			case 412: "Precondition Failed";
			case 413: "Content Too Large";
			case 414: "URI Too Long";
			case 415: "Unsupported Media Type";
			case 416: "Range Not Satisfiable";
			case 417: "Expectation Failed";
			case 418: "I'm a teapot";
			case 421: "Misdirected Request";
			case 422: "Unprocessable Content";
			case 423: "Locked";
			case 424: "Failed Dependency";
			case 425: "Too Early";
			case 426: "Upgrade Required";
			case 428: "Precondition Required";
			case 429: "Too Many Requests";
			case 431: "Request Header Fields Too Large";
			case 451: "Unavailable For Legal Reasons";

			case 500: "Internal Server Error";
			case 501: "Not Implemented";
			case 502: "Bad Gateway";
			case 503: "Service Unavailable";
			case 504: "Gateway Timeout";
			case 505: "HTTP Version Not Supported";
			case 506: "Variant Also Negotiates";
			case 507: "Insufficient Storage";
			case 508: "Loop Detected";
			case 510: "Not Extended";
			case 511: "Network Authentication Required";

			case 6838: "Damn.. you really knew my old discord ID.";
			case 117: "Were it so easy.";

			default: "I'm a dragon";
		}
	}
}
