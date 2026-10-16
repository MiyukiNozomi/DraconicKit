package shinku.std;

using StringTools;

class URLSearchParams {
	private var map:Array<{key:String, value:String}>;

	public function new(search:String) {
		this.map = new Array();

		// let's parse!
		if (search.startsWith("?")) {
			search = search.substring(1);
		}
		final segments = search.split("&").filter(v -> v.length > 0);

		for (segment in segments) {
			var separator = segment.indexOf("=");
			var key = URL.decodeURIComponent((separator == -1 ? segment : segment.substring(0, separator)).replace("+", " "));
			var value = (separator == -1 ? "" : URL.decodeURIComponent(segment.substring(separator + 1).replace("+", " ")));

			this.append(key, value);
		}
	}

	public function sort() {
		this.map.sort((a, b) -> Reflect.compare(a, b));
	}

	public function append(key:String, value:String) {
		this.map.push({key: key, value: value});
	}

	public function has(key:String) {
		final ky = URL.decodeURIComponent(key);
		for (entry in map) {
			if (entry.key == ky)
				return true;
		}
		return false;
	}

	public function get(key:String, ?def:Null<String>):Null<String> {
		final ky = URL.decodeURIComponent(key);
		for (entry in map) {
			if (entry.key == ky)
				return entry.value;
		}
		return def;
	}

	public function toString():String {
		var parts = [];

		for (entry in this.map) {
			var str = URL.encodeURIComponent(entry.key);
			if (entry.value.length > 0) {
				str += '=${URL.encodeURIComponent(entry.value).replace("%20", "+")}';
			}
			parts.push(str);
		}

		return parts.join("&");
	}
}
