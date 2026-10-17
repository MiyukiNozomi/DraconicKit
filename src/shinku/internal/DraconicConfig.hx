package shinku.internal;

import shinku.Console.Logger;
import sys.FileSystem;
import haxe.io.Path;

typedef DraconicConfig = {
	builder:{
		typescriptSupport:Bool,
	},
	server:{
		logging:{
			debugLogs:Bool, showTimestamps:Bool, useColorsInLogs:Bool,
		}, host:String, port:Int, static_dir:String,
	}
}

class DraconicJSConfigLoader {
	public static function getConfig() {
		var draconicConfigPath = FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, "draconic.config.js"]));
		if (!FileSystem.exists(draconicConfigPath)) {
			Logger.error("Config file does not exist at: " + draconicConfigPath + " !");
			return null;
		}

		var output:DraconicConfig = NodeRunner.runNodeScript("configload.js", {
			filename: draconicConfigPath
		});

		return output;
	}

	public static function installConfig(serverConfig:DraconicConfig) {
		Logger.debug("Configuration to install is: ", serverConfig);
		Configuration.SHOW_DEBUG_LOGS = serverConfig.server.logging.debugLogs;
		Configuration.SHOW_TIMESTAMP_LOGS = serverConfig.server.logging.showTimestamps;
		Configuration.USE_COLORS_IN_LOGS = serverConfig.server.logging.useColorsInLogs;

		Configuration.StaticDirectory = serverConfig.server.static_dir;
	}
}
