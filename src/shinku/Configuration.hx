package shinku;

class Configuration {
	public static var Version = "0.1.0";

	public static var ShowDebugLogs = true;
	public static var ShowTimestampLogs = true;
	public static var UseColorsInLogs = true;

	public static var CleanupAlways = true;

	public static var WorkingDirectory:String = "";

	public static var StaticDirectory:String = "static/";

	public static var SvelteBaseHTML:String = "Your thing is broken!";

	public static var CAN_EMIT_ESM_WARNINGS = true;
}
