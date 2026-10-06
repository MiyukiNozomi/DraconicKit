package ryuu.handling;

import haxe.Json;
import haxe.io.Bytes;
import ryuu.http.HttpMessages.HttpResponse;

typedef ResponseOptions = {
	status:Null<Int>,
	headers:Null<Map<String, String>>,
}

abstract class AbstractHandler {
	private function error(status:Int, message:String) {
		// TODO support for custom error pages?
		throw new HttpResponse(status, ["content-type" => "text/plain"], Bytes.ofString(message, haxe.io.Encoding.UTF8));
	}

	private function json(object:Dynamic, options:Null<ResponseOptions> = null) {
		var data = prepareResponse(options);
		if (!data.headers.exists("content-type")) {
			data.headers.set("content-type", "application/json; charset=utf-8");
		}
		throw new HttpResponse(data.status, data.headers, Bytes.ofString(Json.stringify(object), haxe.io.Encoding.UTF8));
	}

	private function text(text:String, options:Null<ResponseOptions> = null) {
		var data = prepareResponse(options);
		if (!data.headers.exists("content-type")) {
			data.headers.set("content-type", "text/plain; charset=utf-8");
		}
		throw new HttpResponse(data.status, data.headers, Bytes.ofString(text, haxe.io.Encoding.UTF8));
	}

	function prepareResponse(options:Null<ResponseOptions>):{
		status:Int,
		headers:Map<String, String>
	} {
		var status = options != null ? options.status : null;
		var headers = options != null ? options.headers : null;
		if (headers == null)
			headers = new Map();
		var safeHeaders = new Map<String, String>();
		for (key => value in headers) {
			safeHeaders.set(key.toLowerCase(), value);
		}
		return {
			status: status == null ? 200 : status,
			headers: safeHeaders
		};
	}
}
