package ryuu;

class Configuration {
	public static var WorkingDirectory:String = "";

	public static var StaticDirectory(default, null):String = "static/";

	public static function loadProjectConfig() {
		// TODO? dragon.json
	}
}
