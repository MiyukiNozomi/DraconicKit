package shinkujs;

import js.html.EventSource;

typedef ModuleDefinition = Dynamic;

@:expose
class ShinkuHotContext {
	var id:String;
	var sse:EventSource;

	public function new(id:String) {
		this.id = id;
		Shinku.log("Hot context created for ", id);

		sse = new EventSource("/@draconickit/ws");

		sse.onmessage = (event) -> {
			#if draconicdev
			Shinku.log("Got an event: ", event);
			#end
		}

		sse.addEventListener("notification", (event) -> {
			#if draconicdev
			Shinku.log("Notification:", event.data);
			#end
		});
	}

	/** 
		accept 
	**/
	public function accept(?arg1:Dynamic, ?arg2:Dynamic):Void {
		if (arg1 == null) {
			acceptSelf();
		} else if (arg2 == null && Reflect.isFunction(arg1)) {
			acceptCallback(arg1);
		} else if (Std.isOfType(arg1, String)) {
			acceptDependency(arg1, arg2);
		} else if (Std.isOfType(arg1, Array)) {
			acceptDependencies(arg1, arg2);
		} else {
			acceptSelf();
		}
	}

	private function acceptSelf():Void {}

	private function acceptCallback(cb:Dynamic):Void {}

	private function acceptDependency(dep:String, cb:Dynamic):Void {}

	private function acceptDependencies(deps:Array<String>, cb:Dynamic):Void {}

	/**
		Rest (because they dont have multiple possibilities)
	**/
	public function dispose(cb:Dynamic):Void {}

	public function prune(cb:Dynamic):Void {}

	public function invalidate(?message:String):Void {}

	public function on(event:String, cb:Dynamic):Void {}

	private function onInternal(event:String, cb:Dynamic):Void {}

	public function off(event:String, cb:Dynamic):Void {}

	private function offInternal(event:String, cb:Dynamic):Void {}

	public function send(event:String, ?data:Dynamic):Void {}
}
