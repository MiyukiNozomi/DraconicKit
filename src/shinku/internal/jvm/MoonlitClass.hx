package shinku.internal.jvm;

#if draconicbuilder
/**
	The name is poetic, a Class<?> is like a dark night. you cant see anything.
	Then the moon shows up and it's reflection of the sun "lights up" the path out of the dark night.

	okay now ignoring the obviously silly description this class is just a helper so I can more easily interop with built haxe classes
**/
class MoonlitClass {
	public var instance(default, null):Dynamic;

	public function new(instance:Dynamic) {
		this.instance = instance;
	}
}
#end
