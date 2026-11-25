package esper.ability.vm;

import esper.ability.vm.Interop.EsperNativeFunction;
import esper.ability.bytecode.Opcodes;
import haxe.ds.StringMap;
import shinku.std.ds.OrderedMap;

enum JSValue {
	// Primitives
	Undefined;
	Null;
	Boolean(v:Bool);
	Number(v:Float);
	String(s:String);

	// Others...
	BigInt(d:Dynamic); // TODO: BigInts
	Symbol(v:JSSymbol);

	Object(v:JSObject);
}

class JSSymbol {
	public var id:Int;
	public var description:Null<String>;

	public function new(id:Int, ?description:String) {
		this.id = id;
		this.description = description;
	}
}

enum PropertyKey {
	Str(s:String);
	Sym(s:JSSymbol);
}

enum PropertyDescriptor {
	Data(value:JSValue, writable:Bool, enumerable:Bool, configurable:Bool);
	Accessor(get:Null<JSObject>, set:Null<JSObject>, enumerable:Bool, configurable:Bool);
}

class PropertyEntry {
	public var key:PropertyKey;
	public var desc:PropertyDescriptor;

	public function new(key:PropertyKey, desc:PropertyDescriptor) {
		this.key = key;
		this.desc = desc;
	}
}

class JSObject {
	public var proto:Null<JSObject>;

	public var properties:OrderedMap<String, Int>; // insertion-ordered
	public var propertyValues:Array<PropertyEntry>;

	public var extensible:Bool = true;
	public var className:String = "Object";

	public function new(?proto:JSObject) {
		this.proto = proto;

		this.properties = new OrderedMap(new Map());
		this.propertyValues = [];
	}

	/**
		public function getOwn(key:PropertyKey):Null<PropertyEntry>
			return propertyValues[properties.get(keyString(key))];
	**/
	// OrderedMap simply wraps a map, and therefore, we must store our keys
	public static inline function keyString(k:PropertyKey):String
		return switch k {
			case Str(s): "s:" + s;
			case Sym(sym): "y:" + sym.id;
		};
}

class Binding {
	public var value:Null<JSValue>; // null = uninitialized (TDZ)
	public var mutable:Bool;

	public function new(mutable:Bool) {
		this.mutable = mutable;
	}
}

class JSEnvironment {
	public var parent:Null<JSEnvironment>;
	public var bindings:StringMap<Binding>;

	public function new(?parent:JSEnvironment) {
		this.parent = parent;
		this.bindings = new StringMap();
	}
}

enum JSFunctionImpl {
	Bytecode(v:EsperFunction, closure:JSEnvironment);
	Native(fn:EsperNativeFunction);
}

class JSFunction extends JSObject {
	// See Bytecode.hx
	public var impl:JSFunctionImpl;
	public var namedParameters:StringMap<Int>;

	public function new(impl:JSFunctionImpl, ?proto:JSObject) {
		super(proto);
		this.impl = impl;
		this.namedParameters = new StringMap();
	}
}
