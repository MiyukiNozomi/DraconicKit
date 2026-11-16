package shinku.internal;

import shinku.internal.js.esm.ESMErrors.ModuleNotFoundError;
import esper.Codegen;
import esper.AstIterator;
import esper.Parser;
#if draconicbuilder
import shinku.Console.Logger;
import sys.FileSystem;
import shinku.internal.js.esm.ESMResolver;
import haxe.io.Path;
import haxe.Json;

using StringTools;

private enum TokenKind {
	Ident;
	Str;
	Trivia; // whitespace + comments
	Punct;
	Other; // numbers, template literals, regex literals
}

private typedef Token = {
	var kind:TokenKind;
	var text:String;
}

class JavaScriptTransformer {
	static final PREAMBLE = "/* inserted by DraconicKit. */ const __draconicImport = (p, o) => { "
		+ "if (!p || (typeof p !== 'string' && !(p instanceof URL))) throw new Error('Bad import path: ' + p); "
		+ "const s = String(p); "
		+ "const u = new URL('/@draconickit/resolve-dynamic/' + s, window.location.origin); "
		+ "u.searchParams.set('draconicKitScriptPath', new URL(import.meta.url).pathname); "
		+ "return import(/^(\\.{1,2}(\\/|$)|\\/|[a-zA-Z][a-zA-Z\\d+.-]*:)/.test(s) ? s : u.href, o); "
		+ "}; ";

	private static function resolveImport(pathname:String, thisPath:String):String {
		try {
			if (ESMResolver.isPathSpecifier(pathname))
				return pathname;
			return Path.join([
				"/@draconickit/module",
				ESMResolver.esmResolve(pathname, FileSystem.absolutePath(thisPath))
			]);
		} catch (err) {
			Logger.error("Could not resolve " + pathname + " because: ", err);
			throw err;
		}
	}

	public static function transform(input:String, thisPath:String):String {
		var program = Parser.parse(input, true);
		var it = new AstIterator(program);

		for (node in it) {
			switch (node.kind) {
				case ImportDeclaration(specifiers, source):
					node.kind = ImportDeclaration(specifiers, resolveImport(source, thisPath));
				case ExportNamedDeclaration(declaration, specifiers, source):
					if (source != null)
						node.kind = ExportNamedDeclaration(declaration, specifiers, resolveImport(source, thisPath));
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

		final output = Codegen.generate(program);

		#if draconicdev
		Logger.debug("======= TRANSFORMATION OF " + thisPath + " =======");
		Logger.debug("====> Transformed script input: \n", input);
		Logger.debug("====> Transformed script output: \n", output);
		Logger.debug("======= END TRANSFORMATION OF " + thisPath + " =======");
		#end

		return PREAMBLE + output;
	}
}
#end
