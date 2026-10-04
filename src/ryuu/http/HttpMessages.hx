package ryuu.http;

import haxe.extern.EitherType;
import haxe.io.Bytes;
import haxe.Exception;
import haxe.Json;
import haxe.io.Input;

typedef HttpRequestStatus = {
	method:String,
	target:String,
	version:String
}

class HttpRequest {
	public var status:HttpRequestStatus;
	public var headers:Map<String, Array<String>>;
	public var payload:Null<Input>;

	public function new(status:HttpRequestStatus, headers:Map<String, Array<String>>) {
		this.status = status;
		this.headers = headers;
	}

	public function getHeader(key:String, df:String = null) {
		var val = this.headers.get(key);
		if (val == null)
			return df;
		return val.join(", ");
	}

	public function toString() {
		return Json.stringify(status) + "\n" + headers.toString();
	}
}

class HttpResponse extends Exception {
	public var status(default, null):Int;
	public var headers(default, null):Map<String, String>;
	public var payload(default, null):Null<EitherType<Input, Bytes>>;

	public function new(status:Int, headers:HttpHeaders = {}, payload:Null<EitherType<Input, Bytes>> = null) {
		super("HttpResponse");
		this.status = status;
		this.headers = new Map<String, String>();

		final fields = Reflect.fields(headers);
		for (field in fields) {
			this.headers.set(field.toLowerCase(), Reflect.getProperty(headers, field));
		}

		this.payload = payload;
	}

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

		headers.set("Server", "Moonlit Crimson Dragon");

		if (this.payload != null) {
			var buffer = Std.downcast(this.payload, Bytes);
			var stream = Std.downcast(this.payload, Input);

			if (buffer != null) {
				headers.set("Content-Length", buffer.length + "");
			} else if (stream != null) {
				headers.set("Transfer-Encoding", "chunked");
			}
		}
	}

	public function statusText():String {
		return switch (this.status) {
			// 1xx Informational
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
			default: "I'm a dragon";
		}
	}
}
