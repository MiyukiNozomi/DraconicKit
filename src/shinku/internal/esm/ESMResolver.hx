package shinku.internal.esm;

import shinku.internal.esm.ESMErrors.UnsupportedDirectoryImportError;
import haxe.io.Path;
import sys.FileSystem;
import shinku.internal.esm.ESMErrors.InvalidModuleSpecifierError;
import shinku.internal.esm.ESMErrors.ModuleNotFoundError;
import shinku.std.URL;

#if windows
#error "Windows is not supported by DraconicKit, consider making a PR, or tell microsoft that \\ for path separators is a bad idea."
#end
using StringTools;

class ESMResolver {
	/**
	 * Returns the project-relative, URI-encoded path of the file `targetPathname`
	 * refers to when imported from `thisScript`.
	 */
	public static function esmResolve(targetPathname:String, thisScript:String):String {
		if (targetPathname.startsWith("node:")) {
			throw new InvalidModuleSpecifierError("Built-in node modules are not allowed in front-end code.");
		}

		// we do not operate on $lib-prefixed pathnames...
		if (isProjectLibPrefix(targetPathname)) {
			return targetPathname;
		}

		// only "./", "../", "/" (and "." / "..") are paths; ".foo" is a bare package name
		if (isPathSpecifier(targetPathname)) {
			return resolvePath(targetPathname, thisScript);
		}

		if (targetPathname.startsWith("#")) {
			return resolveLocalImports(targetPathname, thisScript);
		}

		if (URL.canParse(targetPathname)) {
			return resolveURL(targetPathname, thisScript);
		}

		return toModuleURL(resolveNodeModulePath(targetPathname, thisScript));
	}

	private static function isProjectLibPrefix(spec:String) {
		return spec.startsWith("$lib");
	}

	private static function isPathSpecifier(spec:String):Bool {
		return spec == "." || spec == ".." || spec.startsWith("./") || spec.startsWith("../") || spec.startsWith("/");
	}

	private static function resolveLocalImports(targetPathname:String, thisScript:String):String {
		var packageJson = findThisPackage(thisScript);
		var packageFolder = Path.directory(packageJson);

		var nodePackage = new NodePackage(packageJson);
		var resolved = nodePackage.resolveFromImports(targetPathname, packageFolder, bare -> resolveNodeModulePath(bare, packageJson));
		return toModuleURL(resolved);
	}

	/** Resolves a bare specifier ("pkg", "pkg/sub", "@scope/pkg/sub") to a file path. */
	private static function resolveNodeModulePath(targetPathname:String, thisScript:String):String {
		var parts = targetPathname.split("/");
		var isScoped = targetPathname.startsWith("@");

		if (isScoped && parts.length < 2) {
			throw new InvalidModuleSpecifierError("Invalid package name: " + targetPathname);
		}

		var packageName = isScoped ? parts.slice(0, 2).join("/") : parts[0];
		var subpath = parts.slice(isScoped ? 2 : 1).join("/");

		var packageDir = findPackage(packageName, thisScript);
		var nodePackage = new NodePackage(Path.join([packageDir, "package.json"]));

		return nodePackage.resolve(subpath.length == 0 ? "." : "./" + subpath, packageDir);
	}

	private static function findThisPackage(from:String):String {
		var dir = Path.directory(FileSystem.absolutePath(from));

		while (true) {
			var candidate = Path.join([dir, "package.json"]);
			if (FileSystem.exists(candidate))
				return candidate;

			if (dir == "/" || dir.length == 0)
				break;
			dir = Path.directory(dir);
		}

		throw new ModuleNotFoundError("Couldn't find any parent package.json starting from: " + from);
	}

	private static function findPackage(packageName:String, from:String):String {
		var dir = Path.directory(FileSystem.absolutePath(from));

		while (true) {
			var candidate = Path.join([dir, "node_modules", packageName]);
			if (FileSystem.exists(candidate) && FileSystem.isDirectory(candidate))
				return candidate;

			if (dir == "/" || dir.length == 0)
				break;
			dir = Path.directory(dir);
		}

		throw new ModuleNotFoundError("Couldn't find any parent node_modules that contains: " + packageName);
	}

	private static function resolvePath(targetPathname:String, thisScript:String):String {
		var pathname = if (targetPathname.startsWith("/")) {
			targetPathname;
		} else {
			Path.join([Path.directory(FileSystem.absolutePath(thisScript)), targetPathname]);
		}
		return toModuleURL(pathname);
	}

	private static function resolveURL(targetPathname:String, thisScript:String):String {
		if (!targetPathname.startsWith("file://"))
			throw new InvalidModuleSpecifierError("Cannot use non-file URLs on DraconicKit. (wont build properly): " + targetPathname);

		return toModuleURL(URL.fromFileURL(targetPathname));
	}

	/**
	 * Every resolver funnels through here: checks the file exists, is not a
	 * directory, lives inside the project, and returns it project-relative.
	 */
	private static function toModuleURL(pathname:String):String {
		var absolute = Path.normalize(FileSystem.absolutePath(pathname));

		if (!FileSystem.exists(absolute))
			throw new ModuleNotFoundError("Does not exist on disk: " + absolute);
		if (FileSystem.isDirectory(absolute))
			throw new UnsupportedDirectoryImportError("Cannot import a directory: " + absolute);

		var root = Path.removeTrailingSlashes(Path.normalize(FileSystem.absolutePath("./")));
		if (!absolute.startsWith(root + "/")) {
			throw new InvalidModuleSpecifierError('Cannot import ${absolute} as this absolute directory is outside of this project, which is located at ${root}.');
		}

		return absolute.substr(root.length + 1)
			.split("/")
			.filter(v -> v.length > 0)
			.map(v -> URL.encodeURIComponent(v))
			.join("/");
	}
}
