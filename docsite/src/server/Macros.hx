package server;

import sys.FileSystem;
import haxe.io.Path;
import haxe.macro.Context;

class Macros {
	public static macro function getServeDirectory():haxe.macro.Expr.ExprOf<String> {
		var posInfos = Context.getPosInfos(Context.currentPos());
		var path = FileSystem.absolutePath(Path.normalize(Path.join([Path.directory(posInfos.file), "../template"])));
		return macro $v{path};
	}
}
