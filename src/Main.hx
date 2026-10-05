import ryuu.http.HttpServer;
import sys.net.Host;

class Main {
	static function main() {
		var server = new HttpServer(new Host("localhost"), 6173);

		server.start();
	}
}
