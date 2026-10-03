import sys.net.Host;
import ryuu.http.HttpServer;

class Main {
	static function main() {
		var server = new HttpServer(new Host("localhost"), 6173);

		server.start();
	}
}
