package shinku.handling;

import shinku.handling.RequestHandler.RequestEvent;

typedef ResponseOptions = {
	status:Null<Int>,
	headers:Null<Map<String, String>>,
}

abstract class AbstractServerPage {
	public function new() {}

	public abstract function pageServerLoad(event:RequestEvent):Dynamic;
}

abstract class AbstractHandler extends HandlerTools {}
