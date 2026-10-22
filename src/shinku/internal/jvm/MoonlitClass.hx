package shinku.internal.jvm;

import haxe.Rest;
#if draconicbuilder
import java.lang.reflect.Method;
import haxe.io.Error;

class MoonlitMethod {
	private var parent:MoonlitClass;
	private var method:Method;

	public var name(get, never):String;

	public function new(parent, method) {
		this.parent = parent;
		this.method = method;
	}

	public function getReturnType() {
		return method.getReturnType();
	}

	public function invoke(params:Rest<Dynamic>) {
		if (params.length == 0)
			return method.invoke(this.parent.instance);
		return method.invoke(this.parent.instance, params);
	}

	function get_name():String {
		return method.getName();
	}

	public function toString() {
		return '(method $name of class ${parent.getName()})';
	}
}

/**
	The name is poetic, a Class<?> is like a dark night. you cant see anything.
	Then the moon shows up and it's reflection of the sun "lights up" the path out of the dark night.

	okay now ignoring the obviously silly description this class is just a helper so I can more easily interop with built haxe classes
**/
class MoonlitClass {
	public var instance(default, null):Dynamic;
	public var cls:java.lang.Class<Dynamic>;

	public function new(cls:java.lang.Class<Dynamic>) {
		this.cls = cls;
		this.instance = cls.newInstance();
	}

	public function getName() {
		return this.cls.getCanonicalName();
	}

	public function getRTTI() {}

	public function getMethods(name:String) {
		return this.cls.getMethods()
			.toArray()
			.filter(v -> name.length == 0 || v.getName() == name)
			.map(v -> new MoonlitMethod(this, v));
	}

	/**
		Runs `predicate` if this instance can be downcasted into `type`.
		Returns true if predicate was ran, false if not.
	**/
	public function withType<T:{}, S:T>(target:Class<S>, predicate:(t:S) -> Void):Bool {
		var cs = Std.downcast(this.instance, target);
		if (cs != null) {
			predicate(cs);
			return true;
		}
		return false;
	}

	public function tryCast<T:{}, S:T>(target:Class<S>):Null<S> {
		return Std.downcast(this.instance, target);
	}
}
#end
