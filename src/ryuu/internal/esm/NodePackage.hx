package ryuu.internal.esm;

import ryuu.internal.esm.ESMErrors.InvalidPackageConfigurationError;
import haxe.io.Path;
import haxe.exceptions.NotImplementedException;
import sys.io.File;
import haxe.Json;
import ryuu.internal.esm.ESMErrors.ModuleNotFoundError;
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

	private function joinAndCheckPath(moduleFolder:String, path:String) {
		if (path.startsWith("/")) {
			throw new InvalidPackageConfigurationError("Invalid exports target.");
		}

		var pth = Path.normalize(Path.join([moduleFolder, path])) + "/";
		if (!pth.startsWith(Path.normalize(moduleFolder) + "/")) {
			throw new InvalidPackageConfigurationError("Exports target escapes package boundary.");
		}

		return pth;
	}

	private function resolveExports(subpath:String, moduleFolder:String):String {
		var exports = Reflect.getProperty(data, "exports");
		if (exports == null)
			throw new ModuleNotFoundError("Invalid exports on " + moduleFolder);
		if (!subpath.startsWith("./") && subpath != '.')
			subpath = "./" + subpath;
		return resolveExportsTarget(exports, subpath, moduleFolder);
	}

	private function resolveExportsTarget(exports:Dynamic, subpath:String, moduleFolder:String) {
		if (Std.isOfType(exports, String)) {
			return joinAndCheckPath(moduleFolder, subpath);
		}
		if (Std.isOfType(exports, Array)) {
			var list = cast(exports, Array<Dynamic>);
			for (entry in list) {
				try {
					if (entry == null)
						continue;
					return resolveExportsTarget(entry, subpath, moduleFolder);
				} catch (e:ModuleNotFoundError) {
					continue;
				}
			}
			throw new ModuleNotFoundError("No export target resolved.");
		}

		var isConditions = Reflect.fields(exports).filter(v -> !v.startsWith(".")).length > 0;
		var isSubpaths = Reflect.fields(exports).filter(v -> v.startsWith(".")).length > 0;

		if (isConditions && isSubpaths) {
			throw new InvalidPackageConfigurationError("Module at "
				+ moduleFolder
				+ " has both conditions and subpaths on its exports object. this is disallowed.");
		}

		if (isConditions) {
			for (key in Reflect.fields(exports)) {
				if (conditions.contains(key)) {
					return resolveExportsTarget(Reflect.getProperty(exports, key), subpath, moduleFolder);
				}
			}
		}

		if (isSubpaths) {
			for (key in Reflect.fields(exports)) {
				if (matchPath(key, subpath)) {
					var value = Reflect.field(exports, key);
					var target:Dynamic = value;
					if (Std.isOfType(value, String)) {
						target = substitute(cast(value, String), subpath);
					}
					return resolveExportsTarget(target, subpath, moduleFolder);
				}
			}
		}

		throw new ModuleNotFoundError('Could not locate subpath ${subpath} in module ${moduleFolder}');
	}

	private function substitute(pattern:String, request:String):String {
		var index = pattern.indexOf("*");
		if (index == -1)
			return pattern;

		var prefix = pattern.substr(0, index);
		var suffix = pattern.substr(index + 1);

		var middle = request.substr(prefix.length, request.length - prefix.length - suffix.length);

		return pattern.replace("*", middle);
	}

	private function matchPath(pattern:String, path:String):Bool {
		var p = 0, s = 0, star = -1, mark = 0;
		while (s < path.length) {
			if (p < pattern.length && (pattern.charAt(p) == "?" || pattern.charAt(p) == path.charAt(s))) {
				p++;
				s++;
			} else if (p < pattern.length && pattern.charAt(p) == "*") {
				star = p;
				mark = s;
				p++;
			} else if (star != -1) {
				p = star + 1;
				s = ++mark;
			} else {
				return false;
			}
		}
		while (p < pattern.length && pattern.charAt(p) == "*")
			p++;
		return p == pattern.length;
	}

	public function resolveFromImports(subpath:String, moduleFolder:String) {
		if (Reflect.hasField(data, "imports")) {
			return resolveExportsTarget(data.imports, subpath, moduleFolder);
		}

		throw new InvalidPackageConfigurationError("Package " + moduleFolder + " is attempting to use a imports map without a imports on it's package.json");
	}

	public function resolve(subpath:String, moduleFolder:String) {
		/*if (!Reflect.hasField(data, "type") || Reflect.getProperty(data, "type") != "module") {
			throw new InvalidPackageTargetError("Module at " + moduleFolder + " is not a ES module.");
		}*/
		// trace(subpath, moduleFolder);
		if (Reflect.hasField(data, "exports")) {
			return resolveExports(subpath, moduleFolder);
		}

		if (subpath == ".") {
			if (Reflect.hasField(data, "main"))
				return joinAndCheckPath(moduleFolder, Reflect.getProperty(data, "main"));
			throw new ModuleNotFoundError("No 'main' in package: " + moduleFolder);
		}

		return joinAndCheckPath(moduleFolder, subpath);
	}
}
