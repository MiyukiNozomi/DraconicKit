package esper.transformation;

class ESMRecompiler {
	public static function transform(input:String, pathname:String) {
		return JavaScriptTransformer.transform(input, pathname, false);
	}
}
