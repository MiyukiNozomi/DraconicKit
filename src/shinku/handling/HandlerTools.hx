package shinku.handling;

import haxe.Json;
import haxe.io.Bytes;
import shinku.http.HttpMessages.HttpResponse;
import shinku.handling.AbstractHandler;

class HandlerTools {
	private function error(status:Int, ?message:String = null) {
		// TODO support for custom error pages?
		throw new HttpResponse(status, ["content-type" => ["text/plain"]], Bytes.ofString(message ?? "Error " + status, haxe.io.Encoding.UTF8));
	}

	private function json(object:Dynamic, options:Null<ResponseOptions> = null) {
		var data = prepareResponse(options);
		if (!data.headers.exists("content-type")) {
			data.headers.set("content-type", ["application/json; charset=utf-8"]);
		}
		throw new HttpResponse(data.status, data.headers, Bytes.ofString(Json.stringify(object), haxe.io.Encoding.UTF8));
	}

	private function text(text:String, options:Null<ResponseOptions> = null) {
		var data = prepareResponse(options);
		if (!data.headers.exists("content-type")) {
			data.headers.set("content-type", ["text/plain; charset=utf-8"]);
		}
		throw new HttpResponse(data.status, data.headers, Bytes.ofString(text, haxe.io.Encoding.UTF8));
	}

	private function bytes(bytes : Bytes, options:Null<ResponseOptions> = null) {
		var data = prepareResponse(options);
		throw new HttpResponse(data.status, data.headers, bytes);
	}

	function prepareResponse(options:Null<ResponseOptions>):{
		status:Int,
		headers:Map<String, Array<String>>
	} {
		var status = options != null ? options.status : null;
		var headers = options != null ? options.headers : null;
		if (headers == null)
			headers = new Map();
		var safeHeaders = new Map<String, Array<String>>();
		for (key => value in headers) {
			safeHeaders.set(key.toLowerCase(), [value]);
		}
		return {
			status: status == null ? 200 : status,
			headers: safeHeaders
		};
	}
}
