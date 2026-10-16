package shinku;

class Configuration {
	public static var SHOW_DEBUG_LOGS = false;
	public static var SHOW_TIMESTAMP_LOGS = true;
	public static var USE_COLORS_IN_LOGS = true;

	public static var WorkingDirectory:String = "";

	public static var StaticDirectory:String = "static/";

	public static var SvelteBaseHTML:String = "Your thing is broken!";

	public static var CAN_EMIT_ESM_WARNINGS = true;
}
