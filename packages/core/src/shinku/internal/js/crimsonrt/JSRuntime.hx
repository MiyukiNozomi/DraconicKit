package shinku.internal.js.crimsonrt;

import org.mozilla.javascript.CompilerEnvirons;
import org.mozilla.javascript.Parser;
import haxe.Json;
import org.mozilla.javascript.Context;
import org.mozilla.javascript.ScriptableObject;
import shinku.std.threading.Synchronized;
import sys.io.File;

#if draconicbuilder
class JSRuntime {
	var context:Synchronized<Context>;
	var topLevel:ScriptableObject;

	public function new() {
		final ctx = Context.enter();
		ctx.setLanguageVersion(Context.VERSION_ECMASCRIPT);

		this.topLevel = ctx.initStandardObjects();

		this.context = new Synchronized(ctx);
	}

	public function runModule(pathname:String) {
		final output = this.context.access(cx -> {
			return transform(File.getContent(pathname), pathname);
			// cx.evaluateString(topLevel, 'import ${Json.stringify(content)};', "<crimsonrt>", 1, null);
		});

		trace(output);
	}

	public function transform(text:String, location:String) {
		var env = new CompilerEnvirons();
		env.setLanguageVersion(org.mozilla.javascript.Context.VERSION_ECMASCRIPT);
		env.setRecordingComments(true);

		var parser = new Parser();
		var root = parser.parse(text, location, 1);

		return root.toSource();
	}
}
#end
