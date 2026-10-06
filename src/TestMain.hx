import ryuu.handling.AbstractHandler;
import ryuu.handling.RequestHandler;
import ryuu.Configuration;
import sys.FileSystem;
import ryuu.http.HttpServer;
import sys.net.Host;

class TestHandler extends AbstractHandler {
	public function new() {}

	public function GET(event:RequestEvent) {
		text("Hello?");
	}
}

class TestMain {
	private static function parseInputArguments() {
		var arguments = Sys.args();
		var errorParsing = false;

		while (arguments.length > 0) {
			var arg = arguments.shift() + "";

			if (StringTools.startsWith(arg, "--workdir")) {
				var separator = arg.indexOf("=");
				var directory = "";
				if (separator != -1) {
					directory = arg.substring(separator + 1);
				} else {
					directory = arguments.shift() + "";
				}

				if (!FileSystem.exists(directory)) {
					Sys.println("The specified working directory does not exist: " + directory);
					errorParsing = true;
				}
				Configuration.WorkingDirectory = directory;
			} else {
				Sys.println("This argument is unsupported: " + arg);
				errorParsing = true;
			}
		}

		if (errorParsing) {
			Sys.exit(-5);
		}
	}

	static function main() {
		parseInputArguments();

		var server = new HttpServer(new Host("localhost"), 6173);
		server.requestHandler.addDynamicRoute("/api/test", new TestHandler());
		server.start();
	}
}
