import haxe.Json;
import ryuu.extras.URL;
import sys.net.Host;
import ryuu.http.HttpServer;

class Main {
	static function main() {
		final log = (s:String) -> trace(s);

		trace(URL.encodeURIComponent("hello"));

		trace(URL.encodeURIComponent("hello world"));

		trace(URL.encodeURIComponent("é"));

		trace(URL.encodeURIComponent("😀"));

		trace(URL.decodeURI(URL.encodeURIComponent("hello")));
		trace(URL.decodeURI(URL.encodeURIComponent("hello world")));
		trace(URL.decodeURI(URL.encodeURIComponent("é")));
		trace(URL.decodeURI(URL.encodeURIComponent("😀")));

		var testURL = new URL("https://miyuki:password@eibonantiques.com:4123/weird/../../pathname/banana?whatever&idiot=banana#idiot");
		trace(Json.stringify(testURL));
		trace(testURL.host);
		trace(testURL.origin);
		trace(testURL.href);
		testURL = new URL("https://miyuki:password@[::1]:4123/weird/../../pathname/banana?whatever&idiot=banana#idiot");
		trace(Json.stringify(testURL));
		trace(testURL.host);
		trace(testURL.origin);
		trace(testURL.href);

		log(new URL("./article", "https://test.example.org/api/").href);
		// => https://test.example.org/api/article
		log(new URL("article", "https://test.example.org/api/v1").href);
		// => https://test.example.org/api/article

		trace("==============");

		log(new URL("./story/", "https://test.example.org/api/v2/").href);
		// => https://test.example.org/api/v2/story/
		log(new URL("./story", "https://test.example.org/api/v2/v3").href);
		// => https://test.example.org/api/v2/story

		trace("==============");

		log(new URL("../path", "https://test.example.org/api/v1/v2/").href);
		// => https://test.example.org/api/v1/path
		log(new URL("../../path", "https://test.example.org/api/v1/v2/v3").href);
		// => https://test.example.org/api/path
		log(new URL("../../../../path", "https://test.example.org/api/v1/v2/").href);
		// => https://test.example.org/path

		trace("==============");

		log(new URL("/some/path", "https://test.example.org/api/").href);
		// => https://test.example.org/some/path
		log(new URL("/", "https://test.example.org/api/v1/").href);
		// => https://test.example.org/
		log(new URL("/article", "https://example.com/api/v1/").href);
		// => https://example.com/article

		//		log(new URL("/article", "//localhost/api/v1/").href);
		log(new URL("/article", "https://localhost/api/v1/").href);
		//		log(new URL("/article", "//localhost:5183").href);
		log(new URL("/article", "https://localhost:5183").href);
		log(new URL("https://localhost:5183/need/to/explode").href);

		var server = new HttpServer(new Host("localhost"), 6173);

		server.start();
	}
}
