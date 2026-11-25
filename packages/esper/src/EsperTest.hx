import esper.ability.compiler.Disassembler;
import esper.ability.compiler.Compiler;
import sys.io.File;
import esper.ability.frontend.Parser;
import esper.ability.frontend.AstIterator;
import esper.transformation.JavaScriptTransformer;

using StringTools;

class EsperTest {
	static function main() {
		engineTest();
		// transformTest();
	}

	static function engineTest() {
		final src = File.getContent("test.cjs");

		var it = new AstIterator(Parser.parse(src));

		for (node in it) {
			var indent = StringTools.lpad("", " ", it.lastDepth * 2);
			trace(indent + Type.enumConstructor(node.kind) + ' (line ${node.line}, col ${node.col})');
		}

		final cc = new Compiler("test.cjs");
		var esperFunc = cc.compile(src);

		Disassembler.disassemble(esperFunc);
	}

	static function transformTest() {
		var source = '
			import * as whatever from "svelte";
			import {mount} from "svelte";
			import {compile} from "svelte/compiler";
			await import("fakepath");
		';

		var program = Parser.parse(source, true);

		var it = new AstIterator(program);

		for (node in it) {
			var indent = StringTools.lpad("", " ", it.lastDepth * 2);
			trace(indent + Type.enumConstructor(node.kind) + ' (line ${node.line}, col ${node.col})');
		}

		Sys.println(JavaScriptTransformer.transform(source, "./", true));
	}
}
