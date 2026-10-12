package ryuu.handling;

import ryuu.handling.RequestHandler.RequestEvent;

typedef ResponseOptions = {
	status:Null<Int>,
	headers:Null<Map<String, String>>,
}

abstract class AbstractServerPage {
	public abstract function pageServerLoad(event:RequestEvent):Dynamic;
}

abstract class AbstractHandler extends HandlerTools {}
