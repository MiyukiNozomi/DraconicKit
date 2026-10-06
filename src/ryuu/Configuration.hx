package ryuu;

class Configuration {
	public static var WorkingDirectory:String = "";

	public static var StaticDirectory(default, null):String = "static/";

	public static var RoutesDirectory(default, null):String = "src/routes/";

	public static function loadProjectConfig() {
		// TODO? dragon.json
	}
}
