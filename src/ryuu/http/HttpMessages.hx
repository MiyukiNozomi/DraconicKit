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
	public var status:Int;
	public var headers:Map<String, String>;
	public var payload:Null<EitherType<Input, Bytes>>;

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
}
