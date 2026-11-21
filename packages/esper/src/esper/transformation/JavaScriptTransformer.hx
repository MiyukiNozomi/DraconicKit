package esper.transformation;

import esper.ability.JSStringifier;
import esper.ability.frontend.Parser;
import esper.ability.frontend.AstIterator;
import haxe.io.Path;
import sys.FileSystem;
import shinku.Console.Logger;
import esper.resolution.ESMResolver;

using StringTools;

class JavaScriptTransformer {
	static final BROWSER_PREAMBLE = "/* inserted by DraconicKit. */
const __draconicImport = (p, o) => { 
	if (!p || (typeof p !== 'string' && !(p instanceof URL))) throw new Error('Bad import path: ' + p); 
	const s = String(p); 
	if (/^(\\.{1,2}(\\/|$)|\\/|[a-zA-Z][a-zA-Z\\d+.-]*:)/.test(s)) return import(s, o);
	const u = new URL('/@draconickit/resolve-dynamic/', window.location.origin); 
	u.searchParams.set('draconicKitScriptPath', new URL(import.meta.url).pathname); 
	u.searchParams.set('modulePath', s); 
	return import(u.href, o); 
};
		
";
	static final RHINO_PREAMBLE = "/* inserted by DraconicKit. */
const __draconicImport = (p, o) => { 
	if (!p || (typeof p !== 'string' && !(p instanceof URL))) throw new Error('Bad import path: ' + p); 
	const s = String(p); 
	if (/^(\\.{1,2}(\\/|$)|\\/|[a-zA-Z][a-zA-Z\\d+.-]*:)/.test(s)) return import(s, o);
	return import(import.meta.resolve(s), o); 
};
		
";

	public static function resolveImport(pathname:String, thisPath:String, browser = true):String {
		try {
			if (ESMResolver.isPathSpecifier(pathname))
				return pathname;

			var resolvedPath = ESMResolver.esmResolve(pathname, FileSystem.absolutePath(thisPath));
			return browser ? Path.join(["/@draconickit/module", resolvedPath]) : resolvedPath;
		} catch (err) {
			Logger.error("Could not resolve " + pathname + " because: ", err);
			throw err;
		}
	}

	public static function transform(input:String, thisPath:String, browser = true):String {
		var program = Parser.parse(input, true);
		var it = new AstIterator(program);

		for (node in it) {
			switch (node.kind) {
				case ImportDeclaration(specifiers, source):
					node.kind = ImportDeclaration(specifiers, resolveImport(source, thisPath, browser));
				case ExportNamedDeclaration(declaration, specifiers, source):
					if (source != null)
						node.kind = ExportNamedDeclaration(declaration, specifiers, resolveImport(source, thisPath, browser));
				case ImportExpression(source, options):
					node.kind = CallExpression({
						kind: Identifier('__draconicImport'),
						line: source.line,
						col: source.col
					}, options != null ? [source, options] : [source], false);
				default: // ignore
			}
			//	var indent = StringTools.lpad("", " ", it.lastDepth * 2);
			//	trace(indent + Type.enumConstructor(node.kind) + ' (line ${node.line}, col ${node.col})');
		}

		final output = JSStringifier.stringify(program);

		#if draconicdev
		//  Logger.debug("======= TRANSFORMATION OF " + thisPath + " =======");
		// Logger.debug("====> Transformed script input: \n", input);
		// Logger.debug("====> Transformed script output: \n", output);
		//  Logger.debug("======= END TRANSFORMATION OF " + thisPath + " =======");
		#end

		return (browser ? BROWSER_PREAMBLE : RHINO_PREAMBLE) + output;
	}
}
