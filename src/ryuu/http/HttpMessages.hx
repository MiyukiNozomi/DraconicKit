package ryuu.http;

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
	public var headers:Map<String, String>;
	public var payload:Null<Input>;

	public function new(status:HttpRequestStatus, headers:Map<String, String>) {
		this.status = status;
		this.headers = headers;
	}

	public function toString() {
		return Json.stringify(status) + "\n" + headers.toString();
	}
}

typedef HeadersInit = {};

class HttpResponse extends Exception {
	public var status:Int;
	public var headers:Map<String, String>;

	public function new(status:Int, headers:HeadersInit = {}) {
		super("HttpResponse");
		this.status = status;
		this.headers = new Map<String, String>();

		final fields = Reflect.fields(headers);
		for (field in fields) {
			this.headers.set(field.toLowerCase(), Reflect.getProperty(headers, field));
		}
	}
}
