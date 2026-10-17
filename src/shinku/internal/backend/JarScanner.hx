package shinku.internal.backend;

import jvm.io.NativeInput;
import haxe.crypto.Sha1;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import java.io.File;
import java.util.jar.JarFile;

using StringTools;

typedef JarScan = {
	hashes:Map<String, String>, // class -> sha1
	deps:Map<String, Array<String>>, // class -> user classes it references
}

class JarScanner {
	static final descRe = ~/L([\w$\/]+);/;

	public static function scan(jarPath:String):JarScan {
		final hashes = new Map<String, String>();
		final raw = new Map<String, Map<String, Bool>>();
		final jar = new JarFile(new File(jarPath));
		try {
			final it = jar.entries();
			while (it.hasMoreElements()) {
				final e = it.nextElement();
				final en = e.getName();
				if (!en.endsWith(".class"))
					continue;
				final name = en.substr(0, en.length - 6).replace("/", ".");
				if (DynamicClassLoader.isParentFirst(name))
					continue;

				var input = new NativeInput(jar.getInputStream(e));
				final bytes = input.readAll();
				hashes.set(name, Sha1.make(bytes).toHex());
				raw.set(name, referencedClasses(bytes));
			}
		} catch (e:Dynamic) {
			jar.close();
			throw e;
		}
		jar.close();

		final deps = new Map<String, Array<String>>();
		for (n => refs in raw)
			deps.set(n, [for (r in refs.keys()) if (r != n && hashes.exists(r)) r]);
		return {hashes: hashes, deps: deps};
	}

	static function referencedClasses(b:Bytes):Map<String, Bool> {
		final i = new BytesInput(b);
		i.bigEndian = true;
		i.readInt32(); // magic
		i.readUInt16(); // minor
		i.readUInt16(); // major
		final count = i.readUInt16();
		final utf = new Array<String>();
		final classIdx = new Array<Int>();
		var idx = 1;
		while (idx < count) {
			final tag = i.readByte();
			switch tag {
				case 1:
					utf[idx] = i.readString(i.readUInt16());
				case 3 | 4:
					i.readInt32();
				case 5 | 6:
					i.readInt32();
					i.readInt32();
					idx++;
				case 7:
					classIdx.push(i.readUInt16());
				case 8 | 16 | 19 | 20:
					i.readUInt16();
				case 9 | 10 | 11 | 12 | 17 | 18:
					i.readInt32();
				case 15:
					i.readByte();
					i.readUInt16();
				case _:
					throw 'unknown constant pool tag $tag';
			}
			idx++;
		}

		final out = new Map<String, Bool>();
		for (ci in classIdx) {
			final s = utf[ci];
			if (s != null && !s.startsWith("["))
				out.set(s.replace("/", "."), true);
		}

		for (s in utf) {
			if (s == null || s.indexOf(";") < 0)
				continue;
			var rest = s;
			while (descRe.match(rest)) {
				out.set(descRe.matched(1).replace("/", "."), true);
				rest = descRe.matchedRight();
			}
		}
		return out;
	}
}
