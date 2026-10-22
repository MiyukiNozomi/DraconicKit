package shinku.handling;

import haxe.io.Error;
import haxe.rtti.Rtti;
import shinku.handling.RequestHandler.RequestEvent;

typedef ResponseOptions = {
	status:Null<Int>,
	headers:Null<Map<String, String>>,
}

@:rtti
class DraconicIntrospection extends HandlerTools {
	/**
		# INTERNAL USAGE ONLY		
		Thou shall not touch this!
	**/
	@:keep public final function getRTTI() {
		final b = Type.getClass(this);
		if (b == null) {
			throw Error.Custom("Type.getClass in getRTTI has returned NULL!");
		}
		return Rtti.getRtti(b);
	}
}

abstract class AbstractServerPage extends DraconicIntrospection {
	public function new() {}

	public abstract function pageServerLoad(event:RequestEvent):Dynamic;
}

abstract class AbstractHandler extends DraconicIntrospection {
	public function new() {}
}
