import esper.AstIterator;
import esper.Parser;
import esper.transformation.JavaScriptTransformer;
import haxe.io.Path;
import org.mozilla.javascript.Context;
import sys.FileSystem;
import sys.io.File;
import testing.Checker;

using StringTools;

class EsperTest {
	static function main() {
		//	transformTest();
		executionTest();
	}

	static function executionTest() {
		var checker = new Checker();
		var context = Context.enter();
		context.setLanguageVersion(Context.VERSION_ES6);

		var scope = context.initStandardObjects();

		scope.put("T", scope, Context.javaToJS(checker, scope));

		for (file in FileSystem.readDirectory("packages/esper/tests").filter(v -> v.endsWith('.js')).map(v -> Path.join(["packages/esper/tests", v]))) {
			trace("Running: " + file);
			var src = File.getContent(file);
			//	trace("Output: ", src);
			context.evaluateString(scope, src, file, 1, null);
			trace("LOADED " + file);
		}

		checker.report();
		Context.exit();
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
