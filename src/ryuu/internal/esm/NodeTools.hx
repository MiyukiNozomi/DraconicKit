package ryuu.internal.esm;

import sys.io.File;
import sys.FileSystem;
import haxe.ds.Either;
import ryuu.internal.esm.ESMErrors.InvalidPackageConfigurationError;
import haxe.Json;
import haxe.io.Path;
import ryuu.internal.esm.ESMResolver.ESMContext;
import ryuu.std.URL;

using StringTools;

class NodeTools {
	// There's a bunch of stuff here, and that's bad
	// TODO: distribute these to other specialized classes?
	public static function fileExists(url:URL) {
		return FileSystem.exists(URL.fromFileURL(url));
	}

	public static function isDirectory(url:URL) {
		return FileSystem.isDirectory(URL.fromFileURL(url));
	}

	public static function readFile(url:URL):Null<String> {
		try {
			return File.getContent(URL.fromFileURL(url));
		} catch (errr) {
			trace(errr);
			return null;
		}
	}

	public static function isFileSystemRoot(url:URL):Bool {
		return url.pathname == "/";
	}

	public static function getParentURL(url:URL):URL {
		var path = Path.directory(URL.fromFileURL(url));
		return new URL("file://" + path);
	}

	public static function secondIndexOf(input:String, searchString:String):Int {
		final firstIndex = input.indexOf(searchString);

		if (firstIndex == -1)
			return -1;

		return input.indexOf(searchString, firstIndex + 1);
	}

	public static function every(exports:Dynamic, predicate:String->Bool):Bool {
		for (key in Reflect.fields(exports)) {
			if (!predicate(key)) {
				return false;
			}
		}
		return true;
	}

	public static function partition<T>(array:Array<T>, predicate:T->Bool):Array<Array<T>> {
		var matched:Array<T> = [];
		var unmatched:Array<T> = [];

		for (item in array) {
			if (predicate(item)) {
				matched.push(item);
			} else {
				unmatched.push(item);
			}
		}

		return [matched, unmatched];
	}

	public static function isObject(value:Dynamic):Bool {
		return value != null && Reflect.isObject(value) && Type.getClass(value) == null;
	}

	/** Lookup scoped package.json based on {@link url}.
	 * @param url The URL.
	 * @param ctx
	 * @returns Resolved URL or null if does not exist.
	 */
	public static function lookupPackageScope(url:Either<URL, String>, ctx:ESMContext):Null<URL> {
		// 1. Let scopeURL be url.
		var scopeURL = switch (url) {
			case Left(v): v;
			case Right(v):
				new URL(v.startsWith("file://") ? v : "file://" + v);
		};

		// 2. While scopeURL is not the file system root,
		while (!isFileSystemRoot(scopeURL)) {
			// 1. Set scopeURL to the parent URL of scopeURL.
			scopeURL = getParentURL(scopeURL);

			final pathSegments = scopeURL.pathname.split("/");

			// 2. If scopeURL ends in a "node_modules" path segment, return null.
			if (pathSegments[pathSegments.length - 1] == "node_modules")
				return null;

			// 3. Let pjsonURL be the resolution of "package.json" within scopeURL.
			final pjsonURL = URL.join(scopeURL, "package.json");

			// 4. if the file at pjsonURL exists, then
			if (fileExists(pjsonURL)) {
				// 1. Return scopeURL.
				return scopeURL;
			}
		}

		// 3. Return null.
		return null;
	}

	/** Reads package.json.
	 * @param packageURL The URL of the package.json file.
	 * @param ctx
	 * @throws {InvalidPackageConfigurationError}
	 * @returns JSON parsed package.json or null if does not exist.
	 */
	public static function readPackageJson(packageURL:URL, ctx:ESMContext):Null<Dynamic> {
		// 1. Let pjsonURL be the resolution of "package.json" within packageURL.
		final pjsonURL = URL.join(packageURL, "package.json");

		final file = readFile(pjsonURL);
		// 2. If the file at pjsonURL does not exist, then
		if (file == null) {
			// 1. Return null.
			return null;
		}

		// 3. If the file at packageURL does not parse as valid JSON, then
		try {
			// 4. Return the parsed JSON source of the file at pjsonURL.
			// TODO add validate object
			return Json.parse(file);
		} catch (e) {
			// 1. Throw an Invalid Package Configuration error.
			throw new InvalidPackageConfigurationError('The file is invalid JSON format at ${URL.fromFileURL(pjsonURL)}', e);
		}
	}

	/** Compares two strings that may contain a wildcard character ('*') and returns a value indicating their order.
	 * @param keyA The first string to compare.
	 * @param keyB The second string to compare.
	 * @returns A negative number if {@link keyA} should come before {@link keyB}, a positive number if {@link keyA} should come after {@link keyB}, or 0 if they are equal.
	 */
	public static function patternKeyCompare(keyA:String, keyB:String):Int {
		// 1. Assert: keyA ends with "/" or contains only a single "*".
		// 2. Assert: keyB ends with "/" or contains only a single "*".
		final indexOfKeyA = keyA.indexOf("*");
		final indexOfKeyB = keyB.indexOf("*");
		// 3. Let baseLengthA be the index of "*" in keyA plus one, if keyA contains "*", or the length of keyA otherwise.
		final baseLengthA = indexOfKeyA > -1 ? indexOfKeyA + 1 : keyA.length;
		// 4. Let baseLengthB be the index of "*" in keyB plus one, if keyB contains "*", or the length of keyB otherwise.
		final baseLengthB = indexOfKeyB > -1 ? indexOfKeyB + 1 : keyB.length;
		// 5. If baseLengthA is greater than baseLengthB, return -1.
		if (baseLengthA > baseLengthB)
			return -1;
		// 6. If baseLengthB is greater than baseLengthA, return 1.
		if (baseLengthB > baseLengthA)
			return 1;
		// 7. If keyA does not contain "*", return 1.
		if (indexOfKeyA == -1)
			return 1;
		// 8. If keyB does not contain "*", return -1.
		if (indexOfKeyB == -1)
			return -1;
		// 9. If the length of keyA is greater than the length of keyB, return -1.
		if (keyA.length > keyB.length)
			return -1;
		// 10. If the length of keyB is greater than the length of keyA, return 1.
		if (keyB.length > keyA.length)
			return 1;
		// 11. Return 0.
		return 0;
	}
}
