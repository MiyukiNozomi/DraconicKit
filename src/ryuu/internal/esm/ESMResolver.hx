/**
	MIT License

	Copyright © 2024 Tomoki Miyauchi

	Permission is hereby granted, free of charge, to any person obtaining a copy of
	this software and associated documentation files (the "Software"), to deal in
	the Software without restriction, including without limitation the rights to
	use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
	the Software, and to permit persons to whom the Software is furnished to do so,
	subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
	FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
	COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
	IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
	CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**/

// Haxe port of https://github.com/TomokiMiyauci/node-esm-resolver
// Thank you, Tomoki Miyauci!
package ryuu.internal.esm;

import ryuu.internal.esm.ESMErrors.PackageImportNotDefinedError;
import haxe.io.Error;
import sys.FileSystem;
import ryuu.internal.esm.Format.ESMFormat;
import ryuu.internal.esm.ESMErrors.UnsupportedDirectoryImportError;
import ryuu.std.RegexpEscape;
import ryuu.std.URL;
import ryuu.std.ds.Set;
import haxe.ds.Either;
import ryuu.internal.esm.ESMErrors.InvalidPackageTargetError;
import ryuu.internal.esm.ESMErrors.PackagePathNotExportedError;
import ryuu.internal.esm.ESMErrors.InvalidPackageConfigurationError;
import ryuu.internal.esm.ESMErrors.ModuleNotFoundError;
import ryuu.internal.esm.ESMErrors.InvalidModuleSpecifierError;

using StringTools;

typedef ESMContext = {
	var experimentalWasmModules:Bool;
	var conditions:Dynamic;
}

typedef PackageJson = {
	?type:String
}

typedef ResolveResult = {
	url:URL,
	format:Format
}

class ESMResolve {
	public static final defaultConditions = ["node", "import"];

	/** Resolves the location of the module.
	 * @param specifier Module specifier.
	 * @param parentURL The URL of the package.json file.
	 * @param ctx
	 * @returns Module format and resolved URL.
	 */
	public static function esmResolve(specifier:String, parentURL:Either<URL, String>, ctx:ESMContext,):ResolveResult {
		ctx.conditions ??= defaultConditions;
		// 1. Let resolved be undefined.
		var resolved:Null<URL> = null;

		// 2. If specifier is a valid URL, then
		if (URL.canParse(specifier)) {
			// 1. Set resolved to the result of parsing and reserializing specifier as a URL.
			resolved = new URL(specifier);
		} // 3. Otherwise, if specifier starts with "/", "./", or "../", then
		else if (["/", "./", "../"].filter((value) -> specifier.startsWith(value)).length > 0) {
			// 1. Set resolved to the URL resolution of specifier relative to parentURL.
			resolved = URL.join(switch (parentURL) {
				case Left(v): v;
				case Right(v): new URL(v.startsWith("file://") ? v : "file://" + v);
			}, specifier);
		} // 4. Otherwise, if specifier starts with "#", then
		else if (specifier.startsWith("#")) {
			// 1. Set resolved to the result of PACKAGE_IMPORTS_RESOLVE(specifier, parentURL, defaultConditions).
			resolved = packageImportsResolve(specifier, parentURL, ctx.conditions, ctx,);
		} // 5. Otherwise,
		else {
			// 1. Note: specifier is now a bare specifier.
			// 2. Set resolved the result of PACKAGE_RESOLVE(specifier, parentURL).
			resolved = packageResolve(specifier, parentURL, ctx);
		}

		// will never happen.. but this way Haxe's null safety wont complain.
		if (resolved == null)
			throw new ModuleNotFoundError("resolved == null");

		// 6. var format be undefined.
		var format:Null<Format> = null;

		// // 7. If resolved is a "file:" URL, then
		if (resolved.protocol == "file:") {
			final pattern = ~/%2F|%5C/;
			// 1. If resolved contains any percent encodings of "/" or "\" ("%2F" and "%5C" respectively), then
			if (pattern.match(resolved.toString())) {
				// 1. Throw an Invalid Module Specifier error.
				throw new InvalidModuleSpecifierError("");
			}

			// 2. If the file at resolved is a directory, then
			if (NodeTools.isDirectory(resolved)) {
				// 1. Throw an Unsupported Directory Import error.
				throw new UnsupportedDirectoryImportError("");
			}

			// 3. If the file at resolved does not exist, then
			if (!NodeTools.fileExists(resolved)) {
				// 1. Throw a Module Not Found error.
				throw new ModuleNotFoundError("");
			}

			// 4. Set resolved to the real path of resolved, maintaining the same URL querystring and fragment components.
			resolved = new URL("file://" + FileSystem.absolutePath(URL.fromFileURL(resolved)));

			// 5. Set format to the result of ESM_FILE_FORMAT(resolved).
			format = ESMFormat.resolve(Left(resolved), ctx);

			// 8. Otherwise,
		} else {
			// 1. Set format the module format of the content type associated with the URL resolved.
			// TODO
		}

		if (format == null)
			throw Error.Blocked;

		// 9. Return format and resolved to the loading phase
		return {
			format: format,
			url: resolved
		};
	}

	/** Resolves the given import {@link specifier} for a package.
	 * @param specifier The specifier of the import to resolve.
	 * @param parentURL The parent URL to resolve the import from.
	 * @param conditions Conditions to match.
	 * @param ctx
	 * @throws {InvalidModuleSpecifierError} If the import specifier is not valid.
	 * @throws {PackageImportNotDefinedError} If the import specifier cannot be resolved.
	 * @returns The resolved import URL.
	 */
	public static function packageImportsResolve(specifier:String, // 1. Assert: specifier begins with "#".
		parentURL:Either<URL, String>,
			conditions:Null<Array<String>>, ctx:ESMContext):URL {
		// 2. If specifier is exactly equal to "#" or starts with "#/", then
		if (specifier == "#" || specifier.startsWith("#/")) {
			// 1. Throw an Invalid Module Specifier error.
			final message = 'Invalid module "${specifier}" is not a valid internal imports specifier name imported from ${URL.fromFileURL(switch(parentURL) {
				case Left(v): v;
				case Right(v) : new URL(v.startsWith("file://") ? v : "file://"+v)
		;	})}';
			throw new InvalidModuleSpecifierError(message);
		}

		// 3. Let packageURL be the result of LOOKUP_PACKAGE_SCOPE(parentURL).
		final packageURL = NodeTools.lookupPackageScope(parentURL, ctx);

		// 4. If packageURL is not null, then
		if (packageURL != null) {
			// 1. Let pjson be the result of READ_PACKAGE_JSON(packageURL).
			final pjson = NodeTools.readPackageJson(packageURL, ctx);

			if (pjson == null)
				throw Error.Custom("pjson == null!");

			// 2. If pjson.imports is a non-null Object, then
			if (NodeTools.isObject(pjson.imports)) {
				if (ctx.conditions == null)
					ctx.conditions = defaultConditions;
				// 1. Let resolved be the result of PACKAGE_IMPORTS_EXPORTS_RESOLVE( specifier, pjson.imports, packageURL, true, conditions).
				final resolved = packageImportExportsResolve(specifier, pjson.imports, Left(packageURL), true, ctx.conditions, ctx,);
				// 2. If resolved is not null or undefined, return resolved.
				if (resolved != null)
					return resolved;
			}
		}

		final message = packageURL != null ? 'Package import specifier "${specifier}" is not defined in package ${URL.fromFileURL(packageURL)}package.json imported from ${URL.fromFileURL(switch(parentURL) {
				case Left(v): v;
				case Right(v) : new URL(v.startsWith("file://") ? v : "file://"+v)
		;	})}' : 'Package import specifier "${specifier}" is not defined imported from ${URL.fromFileURL(switch(parentURL) {
				case Left(v): v;
				case Right(v) : new URL(v.startsWith("file://") ? v : "file://"+v)
		;	})}';
		// 5. Throw a Package Import Not Defined error.
		throw new PackageImportNotDefinedError(message);
	}

	public static function packageSelfResolve(packageName:String, packageSubpath:String, parentURL:Either<URL, String>, ctx:ESMContext,):Null<URL> {
		if (ctx.conditions == null)
			ctx.conditions = defaultConditions;

		// 1. Let packageURL be the result of LOOKUP_PACKAGE_SCOPE(parentURL).
		final packageURL = NodeTools.lookupPackageScope(parentURL, ctx);

		// 2. If packageURL is null, then
		if (packageURL == null) {
			// 1. Return null.
			return null;
		}

		// 3. Let pjson be the result of READ_PACKAGE_JSON(packageURL).
		final pjson = NodeTools.readPackageJson(packageURL, ctx);

		// 4. If pjson is null or if pjson.exports is null or null, then
		if (pjson == null || (!pjson.exports)) {
			// 1. Return null.
			return null;
		}

		// 5. If pjson.name is equal to packageName, then
		if (pjson.name == packageName) {
			// 1. Return the result of PACKAGE_EXPORTS_RESOLVE(packageURL, packageSubpath, pjson.exports, defaultConditions).
			return packageExportsResolve(Left(packageURL), packageSubpath, pjson.exports, ctx.conditions, ctx);
		}

		// 6. Otherwise, return null.
		return null;
	}

	/** Resolves the exports of a package.
	 * @param packageURL The URL of the package.json file.
	 * @param subpath The subpath of the package to resolve.
	 * @param exports Exports field of package.json.
	 * @param conditions Conditions to match.
	 * @param ctx
	 * @throws {InvalidPackageConfigurationError}
	 * @returns The resolved package target.
	 */
	public static function packageExportsResolve(packageURL:Either<URL, String>, subpath:String, exports:Dynamic, conditions:Array<String>, ctx:ESMContext) {
		// 1. If exports is an Object with both a key starting with "." and a key not starting with ".", throw an Invalid Package Configuration error.
		if (NodeTools.isObject(exports)) {
			final keys = Reflect.fields(exports);
			final result = NodeTools.partition(keys, (s) -> s.startsWith("."));
			final startWithPeriod = result[0];
			final others = result[1];

			if (startWithPeriod.length > 0 && others.length > 0) {
				throw new InvalidPackageConfigurationError(switch (packageURL) {
					case Left(v): v.href;
					case Right(v): v;
				});
			}
		}

		// 2. If subpath is equal to ".", then
		if (subpath == ".") {
			// 1. Let mainExport be null.
			var mainExport:Null<Dynamic> = null;

			// 2. If exports is a String or Array, or an Object containing no keys starting with ".", then
			if (Type.enumEq(Type.typeof(exports), TClass(String))
				|| Std.isOfType(exports, Array)
				|| (NodeTools.isObject(exports) && NodeTools.every(exports, (k) -> !k.startsWith(".")))) {
				// 1. Set mainExport to exports.
				mainExport = exports;
			} // 3. Otherwise if exports is an Object containing a "." property, then
			else if (NodeTools.isObject(exports) && Reflect.fields(exports).contains(".")) {
				// 1. Set mainExport to exports["."].
				mainExport = Reflect.getProperty(exports, ".");
			}

			// 4. If mainExport is not null, then
			if (mainExport != null) {
				// 1. Let resolved be the result of PACKAGE_TARGET_RESOLVE( packageURL, mainExport, null, false, conditions).
				final resolved = packageTargetResolve(packageURL, mainExport, null, false, conditions, ctx,);
				// 2. If resolved is not null or null, return resolved.
				if (resolved != null)
					return resolved;
			}
		} // 3. Otherwise, if exports is an Object and all keys of exports start with ".", then
		else if (NodeTools.isObject(exports) && NodeTools.every(exports, (k) -> k.startsWith('.'))) {
			// 1. Assert: subpath begins with "./".
			// 2. Let resolved be the result of PACKAGE_IMPORTS_EXPORTS_RESOLVE( subpath, exports, packageURL, false, conditions).
			final resolved = packageImportExportsResolve(subpath, exports, packageURL, false, conditions, ctx);
			// 3. If resolved is not null or null, return resolved.
			if (resolved != null)
				return resolved;
		}

		final path = URL.fromFileURL(new URL(".", switch (packageURL) {
			case Left(v): v.href;
			case Right(v):
				v;
		}));

		final message = subpath == "." ? 'No "exports" main defined in ${path}package.json' : 'Package subpath "${subpath}" is not defined by "exports" in ${path}package.json';

		// 4. Throw a Package Path Not Exported error.
		throw new PackagePathNotExportedError(message);
	}

	/** Resolves `imports` or `exports` field in package.json.
	 * @param matchKey
	 * @param matchObj
	 * @param packageURL The URL of the package.json file.
	 * @param isImports
	 * @param conditions Conditions to match.
	 * @param ctx
	 * @throws {InvalidPackageTargetError}
	 * @returns Resolved URL or nill.
	 */
	public static function packageImportExportsResolve(matchKey:String, matchObj:Dynamic, packageURL:Either<URL, String>, isImports:Bool,
			conditions:Array<String>, ctx:ESMContext):Null<URL> {
		function hasSinglePattern(input:String, pattern:String):Bool {
			var escaped = RegexpEscape.escape(pattern);
			var regexp = new EReg(escaped, "g");

			var count = 0;
			while (regexp.match(input)) {
				count++;

				if (count > 1) {
					return false;
				}

				// Advance past the previous match to find the next one.
				var matched = regexp.matched(0);
				var pos = regexp.matchedPos();

				// Prevent infinite loops for zero-length matches.
				var nextPos = pos.pos + (matched.length > 0 ? matched.length : 1);

				if (nextPos > input.length) {
					break;
				}

				input = input.substr(nextPos);
			}

			return count == 1;
		}

		function hasSingleStar(input:String):Bool {
			return hasSinglePattern(input, "*");
		}

		// 1. If matchKey is a key of matchObj and does not contain "*", then
		if (Reflect.fields(matchObj).contains(matchKey) && !matchKey.contains("*")) {
			// 1. Let target be the value of matchObj[matchKey].
			final target = Reflect.getProperty(matchObj, matchKey);
			// 2. Return the result of PACKAGE_TARGET_RESOLVE(packageURL, target, null, isImports, conditions).
			return packageTargetResolve(packageURL, target, null, isImports, conditions, ctx,);
		}
		// 2. Let expansionKeys be the list of keys of matchObj containing only a single "*", sorted by the sorting function PATTERN_KEY_COMPARE which orders in descending order of specificity.
		var expansionKeys = Reflect.fields(matchObj).filter(hasSingleStar);
		expansionKeys.sort(NodeTools.patternKeyCompare);
		expansionKeys.reverse();
		// 3. For each key expansionKey in expansionKeys, do
		for (expansionKey in expansionKeys) {
			final firstIndex = expansionKey.indexOf("*");
			// 1. Let patternBase be the substring of expansionKey up to but excluding the first "*" character.
			final patternBase = expansionKey.substring(0, firstIndex); // TODO Test
			// 2. If matchKey starts with but is not equal to patternBase, then
			if (matchKey.startsWith(patternBase) && matchKey != patternBase) {
				// 1. Let patternTrailer be the substring of expansionKey from the index after the first "*" character.
				final patternTrailer = expansionKey.substring(firstIndex);
				// 2. If patternTrailer has zero length, or if matchKey ends with patternTrailer and the length of matchKey is greater than or equal to the length of expansionKey, then
				if (patternTrailer.length == 0 || (matchKey.endsWith(patternTrailer) && matchKey.length >= expansionKey.length)) {
					// 1. Let target be the value of matchObj[expansionKey].
					final target = Reflect.getProperty(matchObj, expansionKey);
					// 2. Let patternMatch be the substring of matchKey starting at the index of the length of patternBase up to the length of matchKey minus the length of patternTrailer.
					final patternMatch = matchKey.substring(patternBase.length, matchKey.length - patternTrailer.length,);
					// 3. Return the result of PACKAGE_TARGET_RESOLVE(packageURL, target, patternMatch, isImports, conditions).
					return packageTargetResolve(packageURL, target, patternMatch, isImports, conditions, ctx,);
				}
			}
		}
		// 4. Return null.
		return null;
	}

	/** Resolves the target of a package based on the provided parameters.
	 * @param packageURL The URL of the package.json file.
	 * @param target The target to resolve.
	 * @param patternMatch The pattern to match.
	 * @param isImports
	 * @param conditions Conditions to match.
	 * @param ctx
	 * @throws {InvalidPackageTargetError}
	 * @returns The resolved target, or null if not found, or null if not resolvable.
	 */
	public static var PackageTargets = Set.createString(["", ".", "..", "node_modules"]);

	public static function packageTargetResolve(packageURL:Either<URL, String>, target:Dynamic, patternMatch:Null<String>, isImports:Bool,
			conditions:Array<String>, ctx:ESMContext,):Null<URL> {
		final pattern = ~/[\/\\]/;
		// 1. If target is a String, then
		if (Type.enumEq(Type.typeof(target), TClass(String))) {
			// 1. If target does not start with "./", then
			if (!target.startsWith("./")) {
				// 1. If isImports is false, or if target starts with "../" or "/", or if target is a valid URL, then
				if (!isImports || target.startsWith("../") || target.startsWith("/") || URL.canParse(target)) {
					// 1. Throw an Invalid Package Target error.
					throw new InvalidPackageTargetError("");
				}
				// 2. If patternMatch is a String, then
				if (Type.enumEq(Type.typeof(patternMatch), TClass(String))) {
					final replaced = target.replaceAll("*", patternMatch);

					// 1. Return PACKAGE_RESOLVE(target with every instance of "*" replaced by patternMatch, packageURL + "/").
					return packageResolve(replaced, Left(URL.join(switch (packageURL) {
						case Left(v): v;
						case Right(v): new URL(v.startsWith("file://") ? v : "file://" + v);
					}, "/")), ctx);
				}
				// 3. Return PACKAGE_RESOLVE(target, packageURL + "/").
				return packageResolve(target, Left(URL.join(switch (packageURL) {
					case Left(v): v;
					case Right(v): new URL(v.startsWith("file://") ? v : "file://" + v);
				}, "/")), ctx);
			}

			final splitted = cast(target.split(pattern), Array<Dynamic>);
			// 2. If target split on "/" or "\" contains any "", ".", "..", or "node_modules" segments after the first "." segment, case insensitive and including percent encoded variants, throw an Invalid Package Target error.
			for (segment in splitted.slice(splitted.indexOf(".") + 1).map(URL.decodeURI).map(v -> v.toLowerCase()))
				if (PackageTargets.exists(segment))
					throw new InvalidPackageTargetError("");

			// 3. Let resolvedTarget be the URL resolution of the concatenation of packageURL and target.
			final resolvedTarget = URL.join(switch (packageURL) {
				case Left(v): v;
				case Right(v): new URL(v.startsWith("file://") ? v : "file://" + v);
			}, target);

			// 4. Assert: packageURL is contained in resolvedTarget.

			// 5. If patternMatch is null, then
			if (patternMatch == null) {
				// 1. Return resolvedTarget.
				return resolvedTarget;
			}

			// 6. If patternMatch split on "/" or "\" contains any "", ".", "..", or "node_modules" segments, case insensitive and including percent encoded variants, throw an Invalid Module Specifier error.
			for (segment in pattern.split(patternMatch).map(URL.decodeURI).map(v -> v.toLowerCase()))
				if (PackageTargets.exists(segment))
					throw new InvalidModuleSpecifierError("");

			// 7. Return the URL resolution of resolvedTarget with every instance of "*" replaced with patternMatch.
			return new URL(resolvedTarget.toString().replace("*", patternMatch));

			// 2. Otherwise, if target is a non-null Object, then
		} else if (NodeTools.isObject(target)) {
			// 1. If target contains any index property keys, as defined in ECMA-262 6.1.7 Array Index, throw an Invalid Package Configuration error.
			// TODO

			// 2. For each property p of target, in object insertion order as,
			for (p in Reflect.fields(target)) {
				// 1. If p equals "default" or conditions contains an entry for p, then
				if (p == "default" || Set.createString(conditions).exists(p)) {
					// 1. Let targetValue be the value of the p property in target.
					final targetValue = Reflect.getProperty(target, p);

					// 2. Let resolved be the result of PACKAGE_TARGET_RESOLVE( packageURL, targetValue, patternMatch, isImports, conditions).
					final resolved = packageTargetResolve(packageURL, targetValue, patternMatch, isImports, conditions, ctx);

					// 3. If resolved is equal to null, continue the loop.
					if (resolved == null)
						continue;

					// 4. Return resolved.
					return resolved;
				}
			}

			// 3. Return null.
			return null;
		} // 3. Otherwise, if target is an Array, then
		else if (Std.isOfType(target, Array)) {
			// 1. If _target.length is zero, return null.
			if (!target.length)
				return null;

			var arrayTarget = cast(target, Array<Dynamic>);

			// 2. For each item targetValue in target, do
			for (targetValue in arrayTarget) {
				// 1. Let resolved be the result of PACKAGE_TARGET_RESOLVE( packageURL, targetValue, patternMatch, isImports, conditions), continuing the loop on any Invalid Package Target error.
				try {
					final resolved = packageTargetResolve(packageURL, targetValue, patternMatch, isImports, conditions, ctx);

					// 2. If resolved is null, continue the loop.
					if (resolved == null)
						continue;

					// 3. Return resolved.
					return resolved;
				} catch (err) {
					// continuing the loop on any Invalid Package Target error.
					trace(err);
				}
			}
			// 3. Return or throw the last fallback resolution null return or error.
			return null;
		} // 4. Otherwise, if target is null, return null.
		else if (target == null)
			return null;

		// 5. Otherwise throw an Invalid Package Target error.
		throw new InvalidPackageTargetError("");
	}

	/** Resolves a package specifier to a URL.
	 * @param packageSpecifier The package specifier to resolve.
	 * @param parentURL The parent URL to use for resolution.
	 * @param ctx
	 * @throws {InvalidModuleSpecifierError}
	 * @returns The resolved URL.
	 */
	public static function packageResolve(packageSpecifier:Null<String>, parentURL:Either<URL, String>, ctx:ESMContext):Null<URL> {
		if (ctx.conditions == null)
			ctx.conditions = defaultConditions;

		// 1. Let packageName be null.
		var packageName:Null<String> = null;

		// 2. If packageSpecifier is an empty string, then
		if (packageSpecifier == null) {
			// 1. Throw an Invalid Module Specifier error.
			throw new InvalidModuleSpecifierError("Module specifier must be a non-empty string",);
		}

		// 3. If packageSpecifier is a Node.js builtin module name, then
		/*
			 	We dont support built in modules..

			  if (isBuiltin(packageSpecifier)) {
			// 1. Return the string "node:" concatenated with packageSpecifier.
			return new URL('node:${packageSpecifier}');
		}*/

		// 4. If packageSpecifier does not start with "@", then
		if (!packageSpecifier.startsWith("@")) {
			final index = packageSpecifier.indexOf("/");

			// 1. Set packageName to the substring of packageSpecifier until the first "/" separator or the end of the string.
			packageName = index != -1 ? packageSpecifier.substring(0, index) : packageSpecifier;
		} // 5. Otherwise,
		else {
			// 1. If packageSpecifier does not contain a "/" separator, then
			if (!packageSpecifier.contains("/")) {
				// 1. Throw an Invalid Module Specifier error.
				throw new InvalidModuleSpecifierError('Module specifier is invalid. Received "${packageSpecifier}"');
			}

			final index = NodeTools.secondIndexOf(packageSpecifier, "/");
			// 2. Set packageName to the substring of packageSpecifier until the second "/" separator or the end of the string.
			packageName = index != -1 ? packageSpecifier.substring(0, index) : packageSpecifier;
		}

		// 6. If packageName starts with "." or contains "\" or "%", then
		if (packageName.startsWith(".") || packageName.contains("\\") || packageName.contains("%")) {
			// 1. Throw an Invalid Module Specifier error.
			throw new InvalidModuleSpecifierError('Module specifier is invalid. Received "${packageSpecifier}"');
		}

		// 7. Let packageSubpath be "." concatenated with the substring of packageSpecifier from the position at the length of packageName.
		final packageSubpath = '.${packageSpecifier.substring(packageName.length)}';

		// 8. If packageSubpath ends in "/", then
		if (packageSubpath.endsWith("/")) {
			// 1. Throw an Invalid Module Specifier error.
			throw new InvalidModuleSpecifierError('Module specifier is invalid. Received "${packageSpecifier}"');
		}

		// 9. Let selfUrl be the result of PACKAGE_SELF_RESOLVE(packageName, packageSubpath, parentURL).
		final selfUrl = packageSelfResolve(packageName, packageSubpath, parentURL, ctx,);

		// 10. If selfUrl is not null, return selfUrl.
		if (selfUrl != null)
			return selfUrl;

		var sURL = switch (parentURL) {
			case Left(v): v;
			case Right(v): new URL(v.startsWith("file://") ? v : "file://" + v);
		};

		// 11. While parentURL is not the file system root,
		while (!NodeTools.isFileSystemRoot(sURL)) {
			// 1. Let packageURL be the URL resolution of "node_modules/" concatenated with packageSpecifier, relative to parentURL.
			// @remarks: Maybe not `packageSpecifier`, but packageName
			final packageURL = new URL("node_modules/" + packageName, sURL.href);

			// 2. Set parentURL to the parent folder URL of parentURL.
			sURL = NodeTools.getParentURL(sURL);

			// 3. If the folder at packageURL does not exist, then
			if (!NodeTools.fileExists(packageURL)) {
				// 1. Continue the next loop iteration.
				continue;
			}

			// 4. Let pjson be the result of READ_PACKAGE_JSON(packageURL).
			final pjson = NodeTools.readPackageJson(packageURL, ctx);

			// 5. If pjson is not null and pjson.exports is not null or "undefined", then
			if (pjson != null && (pjson.exports != null)) {
				// 1. Return the result of PACKAGE_EXPORTS_RESOLVE(packageURL, packageSubpath, pjson.exports, defaultConditions).
				return packageExportsResolve(Left(packageURL), packageSubpath, pjson.exports, ctx.conditions, ctx);

				// 6. Otherwise, if packageSubpath is equal to ".", then
			} else if (packageSubpath == ".") {
				// 1. If pjson.main is a string, then
				if (pjson != null && Type.enumEq(Type.typeof(pjson.main), TClass(String))) {
					// 1. Return the URL resolution of main in packageURL.
					return URL.join(packageURL, pjson.main);
				}
			}

			// 7. Otherwise,
			// 1. Return the URL resolution of packageSubpath in packageURL.
			return URL.join(packageURL, packageSubpath);
		}

		// 12. Throw a Module Not Found error.
		throw new ModuleNotFoundError('Cannot find module "${packageSpecifier}"');
	}
}
