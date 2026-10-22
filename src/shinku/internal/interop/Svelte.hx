package shinku.internal.interop;

import haxe.Json;
import haxe.crypto.Sha1;
import haxe.io.Error;
import haxe.io.Path;
import shinku.internal.esm.NodeRunner;
import shinku.std.URLSearchParams;
import sys.FileSystem;
import sys.io.File;

#if dev
typedef SvelteCompileResult = {
	/** The compiled JavaScript */
	js:{
		/** The generated code */
		code:String, /** A source map */ map:Dynamic
	},

	/** The compiled CSS */
	css:Null<{
		/** The generated code */
		code:String,
		/** A source map */
		map:Dynamic,
		/** Whether or not the CSS includes global rules */
		hasGlobal:Bool
	}>,

	/** An array of warning objects generated during compilation */
	warnings:Array<Dynamic>,

	/** Metadata about the compiled component */
	metadata:{
		/**
		 * Whether the file was compiled in runes mode.
		 * For compileModule, this is always true.
		 */
		runes:Bool
	},

	/** The AST */
	ast:Dynamic
}

typedef SvelteComponent = {
	etag:String,
	filename:String,
	result:SvelteCompileResult
}

class SvelteBuilder {
	private static var moduleCache = new Map<String, SvelteComponent>();

	private static function compileIfNeeded(pathname:String):SvelteComponent {
		var physicalPathname = Path.join([Configuration.WorkingDirectory, pathname]);
		if (!FileSystem.exists(physicalPathname)) {
			throw Error.Custom("File not found on disk: " + physicalPathname);
		}

		var source = File.getContent(physicalPathname);
		var sourceTag = Sha1.encode(source);

		var cacheEntry = moduleCache.get(pathname);

		if (cacheEntry != null && cacheEntry.etag == sourceTag) {
			return cacheEntry;
		}
		var compileResult:SvelteCompileResult = NodeRunner.runNodeScript("sveltecc.js", {
			src: source,
			filename: pathname,
			preprocessorConfig: null,
			rootDir: FileSystem.absolutePath(Path.join([Configuration.WorkingDirectory, "src/"]))
		});

		var component:SvelteComponent = {
			etag: sourceTag,
			filename: physicalPathname,
			result: compileResult
		};
		moduleCache.set(pathname, component);
		return component;
	}

	/**
		This function simply returns the plain built component without any transformations.
	**/
	public static function getComponent(pathname:String):SvelteComponent {
		return compileIfNeeded(pathname);
	}

	public static function getComponentScript(component:SvelteComponent, routename:String, searchParams:URLSearchParams) {
		var reqType = (searchParams.get("shinkureqtype", "script") + /*stfu null safety! it cant be null!*/ "").toLowerCase();
		return switch (reqType) {
			case "script":
				// for the page's script.. the thing becomes *pretty* annoying. we used to just inject a style tag ourselves
				// for pages, but now for both components and pages we inject a CSS import.
				JavaScriptTransformer.transform('${component.result.css != null ? 'import "${routename}?shinkureqtype=style";\n' : ''}${component.result.js.code}',
					component.filename);
			case "style":
				// yes, we also turn CSS into a JS script, only in dev mode though.
				// it's a bit more involved (in the sense that if it's missing we return an empty script)
				component.result.css != null ? '
const css = ${Json.stringify(component.result.css.code)};
const style = document.createElement("style");
style.textContent = css;
document.head.appendChild(style);
export default css;
' : '';
			default:
				throw Error.Custom("Unsupported component information type: " + reqType);
		};
	}
}
#end
