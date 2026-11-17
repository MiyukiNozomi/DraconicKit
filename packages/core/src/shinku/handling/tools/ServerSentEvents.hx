package shinku.handling.tools;

import shinku.std.Streams.PipeClosed;
import haxe.extern.EitherType;
import haxe.io.Error;
import haxe.Json;
import shinku.Console.Logger;
import shinku.scheduling.Executor;
import shinku.std.Streams.PipeOutput;
import shinku.http.HttpMessages.HttpResponse;
import haxe.io.Output;
import shinku.handling.RequestHandler.RequestEvent;

class ServerEventsAction {
	/**
		A helper for writing SSE routes 
	**/
	public static function upgrade(event:RequestEvent<Dynamic>, onConnected:(writer:SSEWriter) -> Void, ?onDisconnect:() -> Void) {
		final output = new PipeOutput();
		final res = new HttpResponse(200, [
			"content-type" => ["text/event-stream"],
			"cache-control" => ["no-cache"],
			"connection" => ["keep-alive"],
			"x-accel-buffering" => ["no"]
		], output.input);

		// please haxe.. fix your null safety logic..
		final safeDisconnect = onDisconnect ?? () -> {};

		res.forceSocketClosure = true;

		Executor.schedule(() -> {
			try {
				onConnected(new SSEWriter(output));
			} catch (p:PipeClosed) {
				// not really an error
			} catch (err) {
				Logger.error(err);
				Logger.error("An exception was thrown inside of the onConnected event of the Server Sent Events Action! (see above)");
				output.close();
			}
			if (onDisconnect != null)
				safeDisconnect();
		});
		throw res;
	}
}

/***

	A writer for Server Sent Events

**/
class SSEWriter {
	var output:Output;

	public function new(output:Output) {
		this.output = output;
	}

	function send(prefix:String, data:String):Void {
		data = data.split("\r\n").join("\n").split("\r").join("\n");

		for (ln in data.split('\n')) {
			output.writeString('$prefix: $ln\n');
		}
		output.writeString('\n');
	}

	/**
		This function will throw if `value` contains newlines.
	**/
	public function id(id:EitherType<String, Int>):Void {
		final value = Std.string(id);
		if (value.indexOf('\n') != -1 || value.indexOf('\r') != -1)
			throw Error.Custom("Cannot have newlines in an ID!");
		output.writeString('id: $value\n\n');
	}

	public function retry(milliseconds:Int):Void {
		if (milliseconds < 0)
			throw Error.Custom("Retry interval cannot be negative!");
		output.writeString('retry: $milliseconds\n\n');
	}

	public function data(data:String) {
		this.send("data", data);
	}

	public function json(dyn:Dynamic) {
		this.data(Json.stringify(dyn));
	}

	/**
		This function will throw if `eventName` contains newlines.
	**/
	public function event(eventName:String, data:String):Void {
		if (eventName.indexOf('\n') != -1 || eventName.indexOf('\r') != -1)
			throw Error.Custom("Cannot have newlines in the event name!");
		output.writeString('event: ${eventName}\n');
		this.data(data);
	}

	/**
		This function will throw if `eventName` contains newlines.
	**/
	public function jsonEvent(eventName:String, dyn:Dynamic) {
		this.event(eventName, Json.stringify(dyn));
	}

	public function comment(value:String):Void {
		this.send("", value);
	}
}
