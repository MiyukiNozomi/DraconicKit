package esper.ability.frontend;

import haxe.io.Error;
import esper.ability.frontend.Ast.Node;

/**
 *  Depth-first, pre-order iterator over every node of an AST.
 *
 *   for (node in new AstIterator(program)) { ... }
 *
 * `lastDepth` gives the nesting depth of the node most recently returned.
 *
 * @author akane
 */
class AstIterator {
	final stack:Array<{node:Node, depth:Int}> = [];

	public var lastDepth(default, null):Int = 0;

	public function new(root:Node) {
		stack.push({node: root, depth: 0});
	}

	public function hasNext():Bool {
		return stack.length > 0;
	}

	public function next():Node {
		var entry = stack.pop();
		if (entry == null)
			throw Error.Custom;
		lastDepth = entry.depth;
		var kids = Ast.children(entry.node);
		var idx = kids.length;
		while (idx-- > 0) {
			stack.push({node: kids[idx], depth: entry.depth + 1});
		}
		return entry.node;
	}
}
