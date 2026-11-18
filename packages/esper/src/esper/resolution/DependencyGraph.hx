package esper.resolution;

import sys.FileSystem;
import sys.io.File;
import shinku.std.URL;
import esper.transformation.JavaScriptTransformer;

class Dependency {
	public var filename:String;
	public var dependencies:Array<String>;
	public var lastModDate:Date;

	public function new(filename:String) {
		this.filename = filename;
		this.dependencies = [];
	}
}

/**
	This module will infact transform before building the graph.
	Do not pass transformed scripts into it.
**/
class DependencyGraph {
	var cache:Map<String, Dependency> = [];

	public function new() {}

	public function resolvePhysicalLocation(filename:String, target:String) {
		if (target.charAt(0) == '.') {
			return new URL(target, "file://" + filename).href.substring("file://".length);
		}
		return target;
	}

	public function ofFile(filename:String, source:String, lastModDate:Date):Dependency {
		var existing = this.cache.get(filename);
		if (existing != null) {
			return existing;
		}

		var dependency = new Dependency(filename);
		this.cache.set(filename, dependency);

		final appendToDependencyList = (source:String) -> {
			final resolved = resolvePhysicalLocation(filename, source);
			if (!dependency.dependencies.contains(resolved)) {
				dependency.dependencies.push(resolved);
				this.ofFile(resolved, File.getContent(resolved), FileSystem.stat(resolved).mtime);
			}
		};

		var program = Parser.parse(JavaScriptTransformer.transform(source, filename, false), true);
		var it = new AstIterator(program);

		for (node in it) {
			switch (node.kind) {
				case ImportDeclaration(specifiers, source):
					appendToDependencyList(source);
				case ExportNamedDeclaration(declaration, specifiers, source):
					if (source != null)
						appendToDependencyList(source);
				case ImportExpression(source, options):
					// TODO?
				default: // ignore
			}
		}

		return dependency;
	}
}
