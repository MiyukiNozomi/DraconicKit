package ryuu.internal.esm;

import ryuu.internal.esm.ESMErrors.UnsupportedDirectoryImportError;
import haxe.io.Path;
import sys.FileSystem;
import ryuu.internal.esm.ESMErrors.InvalidModuleSpecifierError;
import ryuu.internal.esm.ESMErrors.ModuleNotFoundError;
import ryuu.std.URL;

#if windows
#error "Windows is not supported by DraconicKit, consider making a PR, or tell microsoft that \\ for path separators is a bad idea."
#end
using StringTools;

class ESMResolver {
	public static function esmResolve(targetPathname:String, thisScript:String):String {
		if (targetPathname.startsWith("node:")) {
			throw new InvalidModuleSpecifierError("Built-in node modules are not allowed in front-end code.");
		}

		if (targetPathname.startsWith(".") || targetPathname.startsWith("/")) {
			return resolvePath(targetPathname, thisScript);
		}

		if (URL.canParse(targetPathname)) {
			return resolveURL(targetPathname, thisScript);
		}

		if (targetPathname.startsWith("#")) {
			return resolveLocalImports(targetPathname, thisScript);
		}

		return resolveNodeModule(targetPathname, thisScript);
	}

	private static function resolveLocalImports(targetPathname:String, thisScript:String) {
		var parts = targetPathname.split("/");
		var packageName = parts[0];
		var packagePath = parts.slice(1).join("/");

		var packageJson = findThisPackage(thisScript);
		var packageFolder = Path.directory(packageJson);

		var nodePackage = new NodePackage(packageJson);
		return nodePackage.resolveFromImports(targetPathname, packageFolder);
	}

	private static function resolveNodeModule(targetPathname:String, thisScript:String) {
		var parts = targetPathname.split("/");

		var packageName = if (targetPathname.startsWith("@")) parts.slice(0, 2).join("/") else parts[0];
		var packagePath = if (targetPathname.startsWith("@")) parts.slice(2).join("/") else parts.slice(1).join("/");

		var packageDir = findPackage(packageName, thisScript);

		if (!FileSystem.exists(packageDir) || !FileSystem.isDirectory(packageDir)) {
			throw new ModuleNotFoundError("Could not find: " + targetPathname);
		}
		var nodePackage = new NodePackage(Path.join([packageDir, "package.json"]));

		var hasTrailingSlash = targetPathname.endsWith("/");
		if (packagePath.length == 0 && !hasTrailingSlash)
			packagePath = ".";
		else if (hasTrailingSlash)
			packagePath = "./";
		if (packagePath.length == 0 && !hasTrailingSlash)
			packagePath = ".";

		return toModuleURL(nodePackage.resolve(packagePath, packageDir), targetPathname);
	}

	private static function findThisPackage(from:String):String {
		var dir = Path.directory(from);

		while (dir != "/" && dir.length > 0) {
			var candidate = Path.join([dir, "package.json"]);

			if (FileSystem.exists(candidate))
				return candidate;

			dir = Path.directory(dir);
		}

		throw new ModuleNotFoundError("Couldn't find any parent package.json starting from: " + from);
	}

	private static function findPackage(packageName:String, from:String):String {
		var dir = Path.directory(from);

		while (dir != "/" && dir.length > 0) {
			var candidate = Path.join([dir, "node_modules", packageName]);

			if (FileSystem.exists(candidate))
				return candidate;

			dir = Path.directory(dir);
		}

		throw new ModuleNotFoundError("Couldn't find any parent node_modules that contains: " + packageName);
	}

	private static function resolvePath(targetPathname:String, thisScript:String) {
		var asURL = new URL(targetPathname, "file:///" + (thisScript.startsWith("/") ? thisScript.substring(1) : thisScript));
		var pathname = URL.fromFileURL(asURL);
		return toModuleURL(pathname, targetPathname);
	}

	private static function resolveURL(targetPathname:String, thisScript:String) {
		if (!targetPathname.startsWith("file://"))
			throw new InvalidModuleSpecifierError("Cannot use non-file URLs on DraconicKit. (wont build properly): " + targetPathname);

		var pathname = URL.fromFileURL(targetPathname);

		var thisFolder = FileSystem.absolutePath("./");
		if (!pathname.startsWith(thisFolder)) {
			throw new InvalidModuleSpecifierError('Cannot import ${pathname} as this absolute directory is outside of this project, which is located at ${thisFolder}.');
		}
		pathname = pathname.substring(thisFolder.length);

		return toModuleURL(pathname, targetPathname);
	}

	private static function toModuleURL(pathname:String, targetPathname:String) {
		if (!FileSystem.exists(pathname))
			throw new ModuleNotFoundError("Does not exist on disk: " + pathname);
		if (FileSystem.isDirectory(pathname))
			throw new UnsupportedDirectoryImportError("Cannot import a directory: " + pathname);

		return pathname.split("/")
			.filter(v -> v.length > 0)
			.map(v -> URL.encodeURIComponent(v))
			.join("/");
	}
}
