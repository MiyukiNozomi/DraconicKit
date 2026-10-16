#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr.Field;
import sys.FileSystem;

class IncludeAll {
	static final PACKAGE_RE = ~/^[a-z_][a-zA-Z0-9_]*$/;
	static final MODULE_RE = ~/^[A-Z][a-zA-Z0-9_]*$/;

	public static function run(relativeDir:String):Array<Field> {
		var file = Context.getPosInfos(Context.currentPos()).file;
		var here = Path.directory(FileSystem.fullPath(file));
		var srcDir = FileSystem.fullPath(Path.join([here, relativeDir]));

		if (!FileSystem.exists(srcDir) || !FileSystem.isDirectory(srcDir))
			Context.fatalError('IncludeAll: directory not found: $srcDir, this is bad!', Context.currentPos());

		var modules:Array<String> = [];
		collect(srcDir, [], modules);

		var self = Context.getLocalModule();
		for (m in modules) {
			if (m == self)
				continue;
			Compiler.keep(m);
			Context.getModule(m);
		}

		return Context.getBuildFields();
	}

	static function collect(dir:String, pack:Array<String>, out:Array<String>):Void {
		for (entry in FileSystem.readDirectory(dir)) {
			var full = Path.join([dir, entry]);
			if (FileSystem.isDirectory(full)) {
				if (PACKAGE_RE.match(entry))
					collect(full, pack.concat([entry]), out);
			} else if (Path.extension(entry) == "hx") {
				var name = Path.withoutExtension(entry);
				if (MODULE_RE.match(name))
					out.push(pack.concat([name]).join("."));
			}
		}
	}
}
#end
