package ryuu.extras;

import haxe.Json;
import haxe.io.BytesBuffer;
import haxe.io.Bytes;
import haxe.io.Error;

/**
	Please be aware that this URL parser might have a few differences from the JS browser implementation of the URL class.
	This is designed to be mostly compliant API-wise though, this URL parser IS NOT the same as the browser one.
	Specially because it's used as a URL parser for our HTTP server implementation.

	## Deviations from the browser URL():

	- One particular limitation here is that the base parameter does not exactly support search and/or fragments.

	- Another deviation is that mailto URLs are normalized into normal URLs. If you put mailto:miyuki@programmer.net it will be normalized into mailto://miyuki@programmer.net.

	- A case with: base = http://old.example/a/b and url  = //new.example/foo in the constructor will not become http://new.example/foo. this was intentional. when the 'base' parameter is present in the constructor it will treat the 'url' as a URL without an origin. which results in http://old.example/new.example/foo

	- (At least in NodeJS) toJSON and toString return the same thing as this.href, but here toJSON returns a stringified JSON version of this class.

	Just a side note: I hate this file and i never want to touch it ever again in my entire life
	I never, EVER want to parse URLs again, it's such a fucking pain!
	With regards, the dragon in the office.

 */
class URL {
	/** A string containing a '#' followed by the fragment identifier of the URL. */
	public var hash:String = "";

	/** A string containing the domain (that is the hostname) followed by (if a port was specified) a ':' and the port of the URL. */
	public var host(get, never):String;

	/** A string containing the domain of the URL. */
	public var hostname:String = "";

	/** A stringifier that returns a string containing the whole URL. */
	public var href(get, set):String;

	/** Returns a string containing the origin of the URL, that is its scheme, its domain and its port. */
	public var origin(get, never):String;

	/** A string containing the password specified before the domain name. */
	public var password:String = "";

	/** A string containing an initial '/' followed by the path of the URL, not including the query string or fragment.
			
		### WARNING
		**Trailing slashes, repeated slashes, "." and ".." path segments may be
		normalized. This class does not preserve the exact path representation
		supplied by the client.**
	 */
	public var pathname:String = "";

	/** A string containing the port number of the URL. */
	public var port:String = "";

	/** A string containing the protocol scheme of the URL, including the final ':'. */
	public var protocol:String = "";

	/** A string indicating the URL's parameter string; if any parameters are provided, this string includes all of them, beginning with the leading ? character. */
	public var search:String = "";

	/** A URLSearchParams object which can be used to access the individual query parameters found in search. */
	// public var searchParams(default, null):URLSearchParams;

	/** A string containing the username specified before the domain name. */
	public var username:String = "";

	public function new(url:String, base:Null<String> = null) {
		trace("Working with: ", url, base);
		if (base != null) {
			var trueBase = findTrueBase(base);
			if (url.length == 0) {
				url = "/"; // just so it wont resolve badly.
			}
			this.parse(url, trueBase, base.substring(trueBase.length));
		} else {
			this.set_href(url);
		}
	}

	private function findTrueBase(src:String) {
		var doubleSlash = src.indexOf("//");
		if (doubleSlash == -1 && StringTools.startsWith(src, "mailto:")) {
			// whoever decided that would be a good idea... has to be murdered.
			// seriously!
			// punk, couldn't we have mailto:// ? seriously?
			src = "mailto://" + src.substring("mailto:".length);
			doubleSlash = src.indexOf("//");
		}
		if (doubleSlash == -1)
			throw Error.Custom("Not a valid http URL: " + src);

		var authorityStart = doubleSlash + 3;

		var slash = src.indexOf("/", authorityStart);
		var query = src.indexOf("?", authorityStart);
		var fragment = src.indexOf("#", authorityStart);

		var end = src.length;

		if (slash != -1 && slash < end)
			end = slash;

		if (query != -1 && query < end)
			end = query;

		if (fragment != -1 && fragment < end)
			end = fragment;

		return src.substring(0, end);
	}

	private function findTruePathname(src:String) {
		var query = src.indexOf("?");
		var fragment = src.indexOf("#");

		var end = src.length;

		if (query != -1 && query < end)
			end = query;

		if (fragment != -1 && fragment < end)
			end = fragment;

		return src.substring(0, end);
	}

	private function parsePort(base:String) {
		var portSeparator = base.indexOf(":");
		if (portSeparator == -1)
			return "";
		var portStr = base.substring(portSeparator + 1);
		base = base.substring(0, portSeparator);
		if (!~/^(?:0|[1-9]\d{0,3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$/.match(portStr))
			throw Error.Custom("Bad URL: Bad Port: " + portStr);
		return portStr;
	};

	private function parse(urlPathname:String, base:String, rootPath:String) {
		if (!StringTools.startsWith(rootPath, "/")) {
			rootPath = "/" + rootPath;
		}

		var truePathname = findTruePathname(urlPathname);
		this.hash = (() -> {
			var fragmentIndex = urlPathname.indexOf("#");
			if (fragmentIndex == -1)
				return "";
			var fragment = urlPathname.substring(fragmentIndex);
			urlPathname = urlPathname.substring(0, fragmentIndex);
			return fragment;
		})();
		this.search = (() -> {
			var searchIndex = urlPathname.indexOf("?");
			if (searchIndex != -1) {
				var search = urlPathname.substring(searchIndex);
				urlPathname = urlPathname.substring(0, searchIndex);
				return search;
			}
			return "";
		})();

		// now that both hash and search are out of the way, let's resolve the pathname.

		// this means absolute, so therefore, our root path should be just "".
		if (StringTools.startsWith(truePathname, "/")) {
			rootPath = "/";
		} else {
			// our pathname starts with ./, we need to remove that.
			if (StringTools.startsWith(truePathname, "./")) {
				truePathname = truePathname.substring(2);
			}
			// now let's resolve it.
			rootPath = rootPath.substring(0, rootPath.lastIndexOf("/") + 1);
		}

		var finalPathComponents = (rootPath
			+ (!StringTools.endsWith(rootPath, "/") && !StringTools.startsWith(truePathname, "/") ? "/" : "")
			+ truePathname).split("/").filter(v -> v.length > 0);

		var builtPath = new Array<String>();
		for (finalPathComponent in finalPathComponents) {
			if (finalPathComponent == "..") {
				if (builtPath.length > 0)
					builtPath.pop();
			} else if (finalPathComponent != ".") {
				builtPath.push(finalPathComponent);
			}
		}

		this.pathname = "/" + builtPath.join("/");

		// time for the "host" segment.

		this.protocol = (() -> {
			var splitter = base.indexOf("://");
			if (splitter == -1) {
				throw Error.Custom("Invalid URL.");
			}
			var proto = base.substring(0, splitter);
			base = base.substring(splitter + 3);
			return proto + ':';
		})();

		{
			var userSplitter = base.lastIndexOf("@");
			if (userSplitter != -1) {
				var segment = base.substring(0, userSplitter);
				base = base.substring(userSplitter + 1);

				var separator = segment.indexOf(":");
				if (separator != -1) {
					this.username = segment.substring(0, separator);
					this.password = segment.substring(separator + 1);
				} else {
					this.username = segment;
				}
			}
		}

		// Is the base IP6? if yes we have to handle it differently.
		if (StringTools.startsWith(base, "[")) {
			var end = base.indexOf("]");
			if (end == -1)
				throw Error.Custom("Incomplete ipv6 address literal: " + base);
			this.hostname = base.substring(0, end + 1);
			base = base.substring(end + 1);
			this.port = parsePort(base);
		} else {
			this.port = parsePort(base);
			// now base should only have the hostname.
			this.hostname = base;
		}
	}

	function get_host():String {
		if (this.port.length > 0) {
			return '${this.hostname}:${this.port}';
		}
		return this.hostname;
	}

	function get_origin():String {
		return '${this.protocol}//${this.host}';
	}

	function set_href(url:String):String {
		var trueBase = findTrueBase(url);
		this.parse(url.substring(trueBase.length), trueBase, "/");
		return this.get_href();
	}

	function get_href():String {
		var base = '${this.protocol}//';
		if (this.username.length > 0) {
			base += this.username;
			if (this.password.length > 0) {
				base += ':' + this.password;
			}
			base += '@';
		}
		base += '${this.get_host()}${(StringTools.startsWith(this.pathname, "/") ? "" : "/") + this.pathname}';

		if (this.search.length > 0) {
			if (!StringTools.startsWith(this.search, '?'))
				base += '?';
			base += this.search;
		}
		if (this.hash.length > 0) {
			if (!StringTools.startsWith(this.hash, '#'))
				base += '#';
			base += this.hash;
		}

		return base;
	}

	/** 
		This function does not return the same thing as the browser one, it actually
		returns this URL as a JSON object containing it's fields.
	**/
	public function toJSON() {
		return Json.stringify({
			href: this.href,
			origin: this.origin,
			protocol: this.protocol,
			username: this.username,
			password: this.password,
			host: this.host,
			hostname: this.hostname,
			port: this.port,
			pathname: this.pathname,
			search: this.search,
			hash: this.hash
		});
	}

	public function toString() {
		return this.href;
	}

	/** 
		Please be aware this function is slightly different than JS's encodeURI.
		Specifically, JS appears not to encode some arbitrary characters,
		in my case? I just do percent encoding like the RFC 3986 specifies.
	 */
	public static function encodeURIComponent(src:String):String {
		final bytes = Bytes.ofString(src);
		var encodedStr = "";

		for (i in 0...bytes.length) {
			final byte = bytes.get(i);

			if ((byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x2E
				|| byte == 0x5F || byte == 0x7E) {
				encodedStr += String.fromCharCode(byte);
			} else {
				encodedStr += "%" + StringTools.hex(byte, 2).toUpperCase();
			}
		}

		return encodedStr;
	}

	/** Please be aware this function may be slightly different than the JS's implementation.*/
	public static function decodeURI(src:String):String {
		final bytes = new BytesBuffer();
		var i = 0;

		while (i < src.length) {
			if (src.charAt(i) == '%') {
				// Need two characters after '%'
				if (i + 2 >= src.length)
					throw "Incomplete percent escape";

				final byte = Std.parseInt("0x" + src.charAt(i + 1) + src.charAt(i + 2));

				if (byte == null)
					throw "Invalid percent escape";
				if (byte < 0)
					throw "Invalid percent escape";

				bytes.addByte(byte);
				i += 3;
			} else {
				var thisCharBytes = Bytes.ofString(src.charAt(i));
				bytes.addBytes(thisCharBytes, 0, thisCharBytes.length);
				i++;
			}
		}

		return bytes.getBytes().toString();
	}
}
