package esper.execution;

import org.mozilla.javascript.Scriptable;
import org.mozilla.javascript.Context;

class EsperRuntime {
	private var context:Context;
	private var globalScope:Scriptable;

	public function new() {
		this.context = Context.enter();
		this.context.setLanguageVersion(Context.VERSION_ECMASCRIPT);

		this.globalScope = this.context.initStandardObjects();
	}
}
