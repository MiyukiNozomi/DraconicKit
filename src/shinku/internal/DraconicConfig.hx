package shinku.internal;

import shinku.internal.esm.NodeRunner;
import shinku.Console.Logger;
import sys.FileSystem;
import haxe.io.Path;

typedef DraconicConfig = {
	builder:{
		typescriptSupport:Bool, alwaysCleanup:Bool,
	},
	server:{
		logging:{
			debugLogs:Bool, showDevRequests:Bool, showTimestamps:Bool, useColorsInLogs:Bool,
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
		#if !draconicdev
		Configuration.ShowDebugLogs = serverConfig.server.logging.debugLogs;
		Configuration.AlwaysCleanup = serverConfig.builder.alwaysCleanup;
		#end
		Configuration.ShowDevRequests = serverConfig.server.logging.showDevRequests;
		Configuration.ShowTimestampLogs = serverConfig.server.logging.showTimestamps;
		Configuration.UseColorsInLogs = serverConfig.server.logging.useColorsInLogs;

		Configuration.StaticDirectory = serverConfig.server.static_dir;
	}
}
