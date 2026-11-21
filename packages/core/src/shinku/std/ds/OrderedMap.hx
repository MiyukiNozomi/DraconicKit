// Modified (and taken) from https://gist.github.com/ruby0x1/84341491930a5df325e7
package shinku.std.ds;

import haxe.Constraints.IMap;

@:nullSafety(Off)
class OrderedMapIterator<K, V> {
	var map:OrderedMap<K, V>;
	var index:Int = 0;

	public function new(omap:OrderedMap<K, V>)
		map = omap;

	public function hasNext():Bool
		return index < map._keys.length;

	public function next():V
		return map.get(map._keys[index++]);
} // OrderedMapIterator

@:nullSafety(Off)
class OrderedMap<K, V> implements IMap<K, V> {
	private var map:Map<K, V>;

	public var _keys(default, null):Array<K>;

	public function new(_map) {
		_keys = [];
		map = _map;
	}

	public function set(key, value) {
		if (_keys.indexOf(key) == -1)
			_keys.push(key);
		map[key] = value;
	}

	public function toString() {
		var _ret = '';
		var _cnt = 0;
		var _len = _keys.length;
		for (k in _keys)
			_ret += '$k => ${map.get(k)}${(_cnt++ < _len - 1 ? ", " : "")}';
		return '{$_ret}';
	}

	public function iterator()
		return new OrderedMapIterator<K, V>(this);

	public function remove(key)
		return map.remove(key) && _keys.remove(key);

	public function exists(key)
		return map.exists(key);

	public function get(key)
		return map.get(key);

	public inline function keys()
		return _keys.iterator();

	public function size():Int
		return map.size();

	public function keyValueIterator():KeyValueIterator<K, V>
		return _keys.map(v -> ({key: v, value: this.map.get(v)})).iterator();

	public function copy():haxe.Constraints.IMap<K, V> {
		var v = new OrderedMap(this.map.copy());
		v._keys = this._keys.map(v -> v);
		return v;
	}

	public function clear() {
		this.map.clear();
		this._keys = [];
	}
} // OrderedMap
