package shinku.internal.jvm;

#if draconicbuilder
import shinku.Console.Logger;
import java.lang.ClassLoader;
import java.net.URL;
import sys.FileSystem;
import sys.thread.Thread;

typedef Generation = {
	hashes:Map<String, String>,
	owners:Map<String, DynamicClassLoader>,
	routes:Map<String, Array<String>>, // class -> route names it installed
}

@:nullSafety(Off)
class HotReloader {
	final parent:ClassLoader = ClassLoader.getSystemClassLoader();

	final handleClass:(cls:java.lang.Class<Dynamic>, className:String) -> Array<String>;

	final removeClass:(route:String) -> Void;

	final live = new Array<{loader:DynamicClassLoader, jar:String}>();
	var current:Generation = null;

	public function new(handleClass, removeClass) {
		this.handleClass = handleClass;
		this.removeClass = removeClass;
	}

	public function reload(jar:String) {
		final t0 = Sys.time();
		final scan = JarScanner.scan(jar);
		final prev = current;

		final changed = new Map<String, Bool>();
		for (n => h in scan.hashes)
			if (prev == null || prev.hashes.get(n) != h)
				changed.set(n, true);
		if (prev != null)
			for (n in prev.hashes.keys())
				if (!scan.hashes.exists(n))
					changed.set(n, true);
		if (prev != null && !changed.keys().hasNext()) {
			try
				FileSystem.deleteFile(jar)
			catch (_) {}
			return;
		}

		final rev = new Map<String, Array<String>>();
		for (n => ds in scan.deps)
			for (d in ds) {
				var l = rev.get(d);
				if (l == null)
					rev.set(d, l = []);
				l.push(n);
			}
		final dirty = new Map<String, Bool>();
		final queue = [for (n in changed.keys()) n];
		while (queue.length > 0) {
			final n = queue.pop();
			if (dirty.exists(n))
				continue;
			dirty.set(n, true);
			final dependents = rev.get(n);
			if (dependents != null)
				for (d in dependents)
					queue.push(d);
		}

		final owners = new Map<String, DynamicClassLoader>();
		final urls = new java.NativeArray<URL>(1);
		urls[0] = new java.io.File(jar).toURI().toURL();
		final next = new DynamicClassLoader(urls, parent, owners);
		for (n in scan.hashes.keys())
			owners.set(n, (prev == null || dirty.exists(n)) ? next : prev.owners.get(n));

		final routes = new Map<String, Array<String>>();
		if (prev != null)
			for (c => names in prev.routes)
				if (!dirty.exists(c))
					routes.set(c, names);

		final installed = new Map<String, Bool>();
		for (n in dirty.keys()) {
			if (!scan.hashes.exists(n) || n.indexOf("$") >= 0)
				continue;
			try {
				final names = handleClass(next.loadClass(n), n);
				if (names.length > 0) {
					routes.set(n, names);
					for (r in names)
						installed.set(r, true);
				}
			} catch (e:Dynamic) {
				Logger.debug('route scan failed for $n: $e');
			}
		}

		if (prev != null)
			for (c => names in prev.routes)
				if (dirty.exists(c))
					for (r in names)
						if (!installed.exists(r))
							removeClass(r);

		live.push({loader: next, jar: jar});
		current = {hashes: scan.hashes, owners: owners, routes: routes};
		final alive = [for (o in owners) o];
		for (g in live.copy())
			if (alive.indexOf(g.loader) < 0) {
				live.remove(g);
				Thread.create(() -> {
					Sys.sleep(10);
					try
						g.loader.close()
					catch (_) {}
					try
						FileSystem.deleteFile(g.jar)
					catch (_) {}
				});
			}

		Logger.debug('reload: ${Lambda.count(changed)} changed, ${Lambda.count(dirty)} dirty, ${Math.round((Sys.time() - t0) * 1000)}ms');
	}
}
#end
