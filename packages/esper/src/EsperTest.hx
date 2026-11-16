import esper.AstIterator;
import esper.Codegen;
import esper.Parser;

class EsperTest {
	static function main() {
		var source = "
			await window.__draconicKit('fakepath');
			await import('fakepath');
			";

		var program = Parser.parse(source, true);

		var it = new AstIterator(program);

		for (node in it) {
			var indent = StringTools.lpad("", " ", it.lastDepth * 2);
			trace(indent + Type.enumConstructor(node.kind) + ' (line ${node.line}, col ${node.col})');

			switch (node.kind) {
				case ExportNamedDeclaration(declaration, specifiers, source):
					trace(declaration, specifiers, source);
				case ExportAllDeclaration(exported, source):
					trace(exported, source);
				case ImportExpression(source, options):
					node.kind = CallExpression({
						kind: MemberExpression({
							kind: Identifier('window'),
							line: source.line,
							col: source.col
						}, {
							kind: Identifier('__draconicKit'),
							line: source.line,
							col: source.col
						}, false, false),
						line: source.line,
						col: source.col
					}, options != null ? [source, options] : [source], false);
				default:
			}
		}

		var it = new AstIterator(program);

		for (node in it) {
			var indent = StringTools.lpad("", " ", it.lastDepth * 2);
			trace(indent + Type.enumConstructor(node.kind) + ' (line ${node.line}, col ${node.col})');
		}
		Sys.println(Codegen.generate(program));
	}
}
