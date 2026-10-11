package ryuu.internal.esm;

import ryuu.internal.esm.ESMErrors.InvalidModuleSpecifierError;
import ryuu.internal.esm.ESMErrors.InvalidPackageConfigurationError;
import ryuu.internal.esm.ESMErrors.ModuleNotFoundError;
import haxe.io.Path;
import sys.io.File;
import haxe.Json;
import sys.FileSystem;

using StringTools;

#if windows
#error "Windows is not supported by DraconicKit, consider making a PR, or tell microsoft that \\ for path separators is a bad idea."
#end
class NodePackage {
	private var data:Dynamic = {};

	#if dev
	private var conditions = ["browser", "import", "development", "default"];
	#else
	private var conditions = ["browser", "import", "production", "default"];
	#end

	public function new(packageJsonFile:String) {
		if (FileSystem.exists(packageJsonFile) && !FileSystem.isDirectory(packageJsonFile)) {
			try {
				this.data = Json.parse(File.getContent(packageJsonFile));
			} catch (e) {
				throw new InvalidPackageConfigurationError("Bad package.json: " + packageJsonFile, e);
			}
		}
	}

	/**
	 * Joins `path` onto `moduleFolder` and makes sure it doesn't escape it.
	 * NOTE: returns a plain file path (no trailing slash).
	 */
	private function joinAndCheckPath(moduleFolder:String, path:String):String {
		if (path.startsWith("/")) {
			throw new InvalidPackageConfigurationError("Invalid exports target: " + path);
		}

		var root = Path.removeTrailingSlashes(Path.normalize(moduleFolder));
		var full = Path.normalize(Path.join([root, path]));
		if (full != root && !full.startsWith(root + "/")) {
			throw new InvalidPackageConfigurationError("Exports target escapes package boundary: " + path);
		}

		return full;
	}

	private function substitute(pattern:String, match:String):String {
		return pattern.replace("*", match);
	}

	/**
	 * Resolves a target (string | array | conditions object | null).
	 * Returns null when nothing matched (so the caller can keep looking).
	 */
	private function resolveTarget(target:Dynamic, match:String, moduleFolder:String, isImports:Bool, resolveBare:Null<String->String>):Null<String> {
		if (target == null)
			return null;

		if (Std.isOfType(target, String)) {
			var t = substitute(cast(target, String), match);
			if (t.startsWith("./"))
				return joinAndCheckPath(moduleFolder, t);

			// "imports" may point at bare specifiers like { "#dep": "some-package" }
			if (isImports && resolveBare != null && !t.startsWith("/") && !t.startsWith("../"))
				return resolveBare(t);

			throw new InvalidPackageConfigurationError('Invalid target "' + t + '" in ' + moduleFolder);
		}

		if (Std.isOfType(target, Array)) {
			var list:Array<Dynamic> = cast target;
			for (entry in list) {
				try {
					var r = resolveTarget(entry, match, moduleFolder, isImports, resolveBare);
					if (r != null)
						return r;
				} catch (e:InvalidPackageConfigurationError) {
					continue;
				}
			}
			return null;
		}

		if (Reflect.isObject(target)) {
			for (key in matchingConditionKeys(target)) {
				var r = resolveTarget(Reflect.field(target, key), match, moduleFolder, isImports, resolveBare);
				if (r != null)
					return r;
			}
			return null;
		}

		throw new InvalidPackageConfigurationError("Invalid target in " + moduleFolder);
	}

	/**
	 * Node picks the first matching condition in the order written in package.json,
	 * but Reflect.fields() doesn't guarantee that order on every Haxe target
	 * (e.g. an alphabetical order puts "default" before "import" and you end up
	 * with the CommonJS build). So rank the conditions instead, following the
	 * convention that specific conditions come first and "default" comes last.
	 */
	private function matchingConditionKeys(obj:Dynamic):Array<String> {
		var keys = Reflect.fields(obj).filter(k -> k == "default" || conditions.contains(k));
		keys.sort((a, b) -> conditionRank(a) - conditionRank(b));
		return keys;
	}

	private function conditionRank(key:String):Int {
		return switch (key) {
			case "development" | "production": 0;
			case "browser": 1;
			case "import": 2;
			case "default": 3;
			default: 4;
		}
	}

	/**
	 * Looks `subpath` up in a map of subpaths (exports / imports).
	 */
	private function resolveMap(map:Dynamic, subpath:String, moduleFolder:String, isImports:Bool, resolveBare:Null<String->String>):String {
		// exact match
		if (subpath.indexOf("*") == -1 && Reflect.hasField(map, subpath)) {
			var r = resolveTarget(Reflect.field(map, subpath), "", moduleFolder, isImports, resolveBare);
			if (r == null)
				throw new ModuleNotFoundError('Subpath ${subpath} has no matching condition in ${moduleFolder}');
			return r;
		}

		// pattern match ("./features/*"), longest prefix wins
		var bestKey:Null<String> = null;
		var bestPrefixLen = -1;
		var bestMatch = "";
		for (key in Reflect.fields(map)) {
			var star = key.indexOf("*");
			if (star == -1 || star != key.lastIndexOf("*"))
				continue;

			var prefix = key.substr(0, star);
			var suffix = key.substr(star + 1);
			if (subpath.length >= key.length && subpath.startsWith(prefix) && subpath.endsWith(suffix) && star > bestPrefixLen) {
				bestKey = key;
				bestPrefixLen = star;
				bestMatch = subpath.substring(prefix.length, subpath.length - suffix.length);
			}
		}

		if (bestKey != null) {
			var r = resolveTarget(Reflect.field(map, bestKey), bestMatch, moduleFolder, isImports, resolveBare);
			if (r == null)
				throw new ModuleNotFoundError('Subpath ${subpath} has no matching condition in ${moduleFolder}');
			return r;
		}

		throw new ModuleNotFoundError('Could not locate subpath ${subpath} in module ${moduleFolder}');
	}

	private function resolveExports(exports:Dynamic, subpath:String, moduleFolder:String):String {
		var map:Dynamic = exports;

		var isObject = !Std.isOfType(exports, String) && !Std.isOfType(exports, Array) && Reflect.isObject(exports);
		var keys = isObject ? Reflect.fields(exports) : [];
		var dotKeys = keys.filter(v -> v.startsWith(".")).length;

		if (dotKeys > 0 && dotKeys != keys.length) {
			throw new InvalidPackageConfigurationError("Module at "
				+ moduleFolder
				+ " has both conditions and subpaths on its exports object. this is disallowed.");
		}

		// sugar: "exports": "./x.js" / [...] / { "import": ... } all mean { ".": <that> }
		if (dotKeys == 0) {
			map = {};
			Reflect.setField(map, ".", exports);
		}

		return resolveMap(map, subpath, moduleFolder, false, null);
	}

	/** Node's fallback when there is no "exports": main, then index.js */
	private function resolveLegacyMain(moduleFolder:String):String {
		var main = "index.js";
		var declared = Reflect.field(data, "main");
		if (declared != null && Std.isOfType(declared, String) && cast(declared, String).length > 0)
			main = declared;

		for (candidate in [main, main + ".js", main + ".json", main + "/index.js", "index.js"]) {
			var p = joinAndCheckPath(moduleFolder, candidate);
			if (FileSystem.exists(p) && !FileSystem.isDirectory(p))
				return p;
		}
		throw new ModuleNotFoundError("Could not find the entry point of package: " + moduleFolder);
	}

	/**
	 * Resolves a "#specifier" using this package's "imports" field.
	 * `resolveBare` is used when an imports target is a bare package name.
	 */
	public function resolveFromImports(specifier:String, moduleFolder:String, ?resolveBare:String->String):String {
		var imports = Reflect.field(data, "imports");
		if (imports == null) {
			throw new InvalidPackageConfigurationError("Package "
				+ moduleFolder
				+ " is attempting to use a imports map without a imports on it's package.json");
		}
		if (specifier == "#" || specifier.startsWith("#/")) {
			throw new InvalidModuleSpecifierError("Invalid imports specifier: " + specifier);
		}

		return resolveMap(imports, specifier, moduleFolder, true, resolveBare);
	}

	/**
	 * `subpath` is "." for the package root, or "./something".
	 */
	public function resolve(subpath:String, moduleFolder:String):String {
		if (subpath != "." && !subpath.startsWith("./"))
			subpath = "./" + subpath;

		var exports = Reflect.field(data, "exports");
		if (exports != null)
			return resolveExports(exports, subpath, moduleFolder);

		if (subpath == ".")
			return resolveLegacyMain(moduleFolder);

		return joinAndCheckPath(moduleFolder, subpath);
	}
}
