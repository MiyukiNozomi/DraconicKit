package shinku.std;

using StringTools;

private typedef URLSearchParam = {key:String, value:String};

class URLSearchParams {
	private var map:Array<URLSearchParam>;

	/**
		Indicates the total number of search parameter entries.
	**/
	public var size(get, never):Int;

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

	/**
		Appends a specified key/value pair as a new search parameter.
	**/
	public function append(key:String, value:String) {
		this.map.push({key: key, value: value});
	}

	/**
		Deletes search parameters that match a name, and optional value, from the list of all search parameters.
	**/
	public function delete(name:String, ?value:String) {
		final ky = URL.decodeURIComponent(name);
		var hasDeleted;
		do {
			hasDeleted = false;
			for (i in 0...this.map.length) {
				var canDelete = this.map[i].key == ky && (if (value != null) this.map[i].value == value else true);
				if (canDelete) {
					hasDeleted = true;
					this.map.remove(this.map[i]);
					break;
				}
			}
		} while (hasDeleted);
	}

	/**
		Returns an iterator allowing iteration through all key/value pairs contained in this object in the same order as they appear in the query string.
	**/
	public function entries() {
		return this.map.iterator();
	}

	/** Returns a boolean value indicating if a given parameter, or parameter and value pair, exists.**/
	public function has(key:String, ?value:String) {
		final ky = URL.decodeURIComponent(key);
		for (entry in map) {
			if (entry.key == ky && (value != null ? entry.value == value : true))
				return true;
		}
		return false;
	}

	/** Returns the first value associated with the given search parameter. **/
	public function get(key:String, ?def:Null<String>):Null<String> {
		final ky = URL.decodeURIComponent(key);
		for (entry in map) {
			if (entry.key == ky)
				return entry.value;
		}
		return def;
	}

	/** Returns the first value associated with the given search parameter. **/
	public function set(key:String, value:String) {
		final ky = URL.decodeURIComponent(key);
		this.delete(ky);
		this.map.push({key: ky, value: value});
	}

	/**Returns all the values associated with a given search parameter.**/
	public function getAll(key:String) {
		final ky = URL.decodeURIComponent(key);
		var lst = new Array<String>();

		for (entry in map) {
			if (entry.key == ky)
				lst.push(entry.value);
		}
		return lst;
	}

	/**Sorts all key/value pairs, if any, by their keys.**/
	public function sort() {
		this.map.sort((a, b) -> Reflect.compare(a.key, b.key));
	}

	/**
		Returns an iterator allowing iteration through all key/value pairs contained in this object in the same order as they appear in the query string.
	**/
	public function iterator()
		return this.map.iterator();

	function get_size():Int
		return this.map.length;

	/** Returns a string containing a query string suitable for use in a URL. **/
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

	/** Returns an iterator allowing iteration through all values of the key/value pairs contained in this object. **/
	public function values() {
		return this.map.map(v -> v.value).iterator();
	}
}
