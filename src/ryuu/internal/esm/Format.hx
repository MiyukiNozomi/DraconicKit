package ryuu.internal.esm;

import haxe.io.Path;
import ryuu.std.URL;
import haxe.ds.Either;
import ryuu.internal.esm.NodeTools.NodeTools;
import ryuu.internal.esm.ESMResolver.ESMContext;

using StringTools;

enum Format {
	Module;
	CommonJS;
	Json;
	Wasm;
}

class ESMFormat {
	/** Resolves file format.
	 * @param surl The URL.
	 * @param ctx
	 */
	public static function resolve(surl:Either<URL, String>, ctx:ESMContext):Null<Format> {
		final url = switch (surl) {
			case Left(v): v;
			case Right(v): new URL(v.startsWith("file://") ? v : "file://" + v);
		};
		final ext = Path.extension(url.pathname);

		// 1. Assert: url corresponds to an existing file.
		// 2. If url ends in ".mjs", then
		if (ext == ".mjs") {
			// 1. Return "module".
			return Module;
		}

		// 3. If url ends in ".cjs", then
		if (ext == ".cjs") {
			// 1. Return "commonjs".
			return CommonJS;
		}

		// 4. If url ends in ".json", then
		if (ext == ".json") {
			// 1. Return "json".
			return Json;
		}

		// 5. If --experimental-wasm-modules is enabled and url ends in ".wasm", then
		if (ctx?.experimentalWasmModules && ext == ".wasm") {
			// 1. Return "wasm".
			return Wasm;
		}

		// 6. Let packageURL be the result of LOOKUP_PACKAGE_SCOPE(url).
		final packageURL = NodeTools.lookupPackageScope(surl, ctx);

		// 7. Let pjson be the result of READ_PACKAGE_JSON(packageURL).
		final pjson = packageURL != null ? NodeTools.readPackageJson(packageURL, ctx) : null;

		// 8. Let packageType be null.
		var packageType:Null<String> = null;
		final type = pjson?.type;

		// 9. If pjson?.type is "module" or "commonjs", then
		if (type == "module" || type == "commonjs") {
			// 1. Set packageType to pjson.type.
			packageType = type;
		}

		// 10. If url ends in ".js", then
		if (ext == ".js") {
			// 1. If packageType is not null, then
			if (packageType != null) {
				// 1. Return packageType.
				return formatFromPackageType(packageType);
			}

			// 2. If --experimental-detect-module is enabled and the source of module contains static import or export syntax, then
			// if (ctx?.experimentalDetectModule) {
			//   // 1. Return "module".
			//   return "module";
			// }

			// 3. Return "commonjs".

			// miyuki: Hah! uh.. nothing i thought it was funny that it's returning an enum member and not a string..
			return CommonJS;
		}

		// 11. If url does not have any extension, then
		if (ext.length == 0) {
			// 1. If packageType is "module" and --experimental-wasm-modules is enabled and the file at url contains the header for a WebAssembly module, then
			// if (packageType === "module" && ctx?.experimentalWasmModules) {
			//   // 1. Return "wasm".
			//   return "wasm";
			// }

			// 2. If packageType is not null, then
			if (packageType != null) {
				// 1. Return packageType.
				return formatFromPackageType(packageType);
			}

			// // 3. If --experimental-detect-module is enabled and the source of module contains static import or export syntax, then
			// // 1. Return "module".
			// return "module";

			// 4. Return "commonjs".
			return CommonJS;
		}

		// 12. Return undefined (will throw during load phase).
		// miyuki: yeah. uh.. undefined.. not a thing here.
		return null;
	}

	private static function formatFromPackageType(packageType:String):Format {
		return switch (packageType) {
			case "module":
				Module;

			case "commonjs":
				CommonJS;

			case "json":
				return Json;

			case "wasm":
				return Wasm;

			default:
				CommonJS;
		}
	}
}
