package shinku.internal.jvm;

#if draconicbuilder
import haxe.io.Error;
import java.io.File;
import java.lang.ClassLoader;
import java.lang.ClassNotFoundException;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.jar.JarFile;
import sys.thread.Mutex;

using StringTools;

class DynamicClassLoader extends URLClassLoader {
	static var serverPackages:Array<String> = [];
	static final alwaysParent = ["java.", "javax.", "jdk.", "sun.", "com.sun."];
	static final serverClasses:Map<String, Bool> = scanServerClasses(Sys.programPath());

	final owners:Map<String, DynamicClassLoader>;
	final mutex = new Mutex();

	public function new(urls:java.NativeArray<URL>, parent:ClassLoader, owners:Map<String, DynamicClassLoader>) {
		super(urls, parent);
		this.owners = owners;
	}

	public static function isParentFirst(name:String):Bool {
		for (p in alwaysParent)
			if (name.startsWith(p))
				return true;
		if (name.startsWith("haxe.generated."))
			return false;
		return serverClasses.exists(name);
	}

	static function scanServerClasses(jarPath:String):Map<String, Bool> {
		final out = new Map<String, Bool>();
		final jar = new JarFile(new File(jarPath));
		try {
			final entries = jar.entries();
			while (entries.hasMoreElements()) {
				final n = entries.nextElement().getName();
				if (n.endsWith(".class"))
					out.set(n.substr(0, n.length - 6).replace("/", "."), true);
			}
		} catch (e:Dynamic) {
			jar.close();
			throw e;
		}
		jar.close();
		return out;
	}

	override overload function loadClass(name:String, resolve:Bool):java.lang.Class<Dynamic> {
		mutex.acquire();
		try {
			var c = findLoadedClass(name);
			if (c == null) {
				if (isParentFirst(name)) {
					try {
						c = getParent().loadClass(name);
					} catch (e:ClassNotFoundException) {
						c = findClass(name);
					}
				} else if (owners.exists(name)) {
					final o = owners.get(name);
					if (o == null)
						throw Error.Blocked;
					c = (o == this) ? findClass(name) : o.loadClass(name);
				} else {
					c = getParent().loadClass(name);
				}
			}
			if (resolve)
				resolveClass(c);
			mutex.release();
			return c;
		} catch (e:Dynamic) {
			mutex.release();
			throw e;
		}
	}
}
#end
