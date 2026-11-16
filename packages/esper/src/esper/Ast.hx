package esper;

typedef Node = {
	var kind:NodeKind;
	var line:Int;
	var col:Int;
}

typedef FunctionData = {
	var name:Null<String>;
	var params:Array<Node>;
	var body:Node; // BlockStatement for functions, and any expression for concise arrows
	var isAsync:Bool;
	var isGenerator:Bool;
	var isArrow:Bool;
	var isExpression:Bool; // is it an arrow function with an expression body?
}

typedef ClassData = {
	var name:Null<String>;
	var superClass:Null<Node>;
	var members:Array<Node>;
}

enum NodeKind {
	Program(body:Array<Node>);

	// Statements
	ExpressionStatement(expression:Node);
	BlockStatement(body:Array<Node>);
	EmptyStatement;
	DebuggerStatement;
	VariableDeclaration(kind:String, declarations:Array<Node>);
	VariableDeclarator(id:Node, init:Null<Node>);
	IfStatement(test:Node, consequent:Node, alternate:Null<Node>);
	ForStatement(init:Null<Node>, test:Null<Node>, update:Null<Node>, body:Node);
	ForInStatement(left:Node, right:Node, body:Node);
	ForOfStatement(left:Node, right:Node, body:Node, isAwait:Bool);
	WhileStatement(test:Node, body:Node);
	DoWhileStatement(body:Node, test:Node);
	ReturnStatement(argument:Null<Node>);
	BreakStatement(label:Null<String>);
	ContinueStatement(label:Null<String>);
	ThrowStatement(argument:Node);
	TryStatement(block:Node, param:Null<Node>, handler:Null<Node>, finalizer:Null<Node>);
	SwitchStatement(discriminant:Node, cases:Array<Node>);
	SwitchCase(test:Null<Node>, consequent:Array<Node>);
	LabeledStatement(label:String, body:Node);
	FunctionDeclaration(fn:FunctionData);
	ClassDeclaration(cls:ClassData);

	// Expressions and Patterns!
	Identifier(name:String);
	PrivateIdentifier(name:String);
	NumberLiteral(value:Float);
	BigIntLiteral(digits:String);
	StringLiteral(value:String);
	BooleanLiteral(value:Bool);
	NullLiteral;
	RegExpLiteral(pattern:String, flags:String);
	TemplateLiteral(cooked:Array<String>, raw:Array<String>, expressions:Array<Node>);
	TaggedTemplateExpression(tag:Node, quasi:Node);
	ThisExpression;
	SuperExpression;
	MetaProperty(meta:String, property:String);
	ArrayExpression(elements:Array<Null<Node>>); // null entries are holes
	ObjectExpression(properties:Array<Node>);
	Property(key:Node, value:Node, computed:Bool, kind:String, shorthand:Bool, method:Bool);
	SpreadElement(argument:Node);
	RestElement(argument:Node);
	ArrayPattern(elements:Array<Null<Node>>);
	ObjectPattern(properties:Array<Node>);
	AssignmentPattern(left:Node, right:Node);
	UnaryExpression(operator_:String, argument:Node);
	UpdateExpression(operator_:String, prefix:Bool, argument:Node);
	BinaryExpression(operator_:String, left:Node, right:Node);
	LogicalExpression(operator_:String, left:Node, right:Node);
	AssignmentExpression(operator_:String, left:Node, right:Node);
	ConditionalExpression(test:Node, consequent:Node, alternate:Node);
	CallExpression(callee:Node, arguments:Array<Node>, optional:Bool);
	NewExpression(callee:Node, arguments:Array<Node>);
	MemberExpression(object:Node, property:Node, computed:Bool, optional:Bool);
	SequenceExpression(expressions:Array<Node>);
	ArrowFunctionExpression(fn:FunctionData);
	FunctionExpression(fn:FunctionData);
	ClassExpression(cls:ClassData);
	YieldExpression(argument:Null<Node>, delegate:Bool);
	AwaitExpression(argument:Node);

	// ES Modules
	WithStatement(object:Node, body:Node);
	ImportDeclaration(specifiers:Array<Node>, source:String);
	ImportDefaultSpecifier(local:String);
	ImportNamespaceSpecifier(local:String);
	ImportSpecifier(imported:String, local:String);
	ImportExpression(source:Node, options:Null<Node>); // import(source, options)
	ExportNamedDeclaration(declaration:Null<Node>, specifiers:Array<Node>, source:Null<String>);
	ExportSpecifier(local:String, exported:String);
	ExportDefaultDeclaration(declaration:Node);
	ExportAllDeclaration(exported:Null<String>, source:String); // export * [as name] from

	// Class related
	MethodDefinition(key:Node, computed:Bool, isStatic:Bool, kind:String, fn:FunctionData);
	PropertyDefinition(key:Node, computed:Bool, isStatic:Bool, value:Null<Node>);
	StaticBlock(block:Node);
}

/**
 * Helpers for working with the AST generically.
 */
class Ast {
	/** Returns the direct child nodes of `n`, in source order. */
	public static function children(n:Node):Array<Node> {
		var out:Array<Node> = [];

		function add(x:Null<Node>) {
			if (x != null)
				out.push(x);
		}
		function addAll(xs:Array<Null<Node>>) {
			for (x in xs)
				add(x);
		}
		function addFn(f:FunctionData) {
			addAll(f.params);
			add(f.body);
		}
		function addClass(c:ClassData) {
			add(c.superClass);
			addAll(c.members);
		}

		switch n.kind {
			case Program(body):
				addAll(body);
			case ExpressionStatement(e):
				add(e);
			case BlockStatement(body):
				addAll(body);
			case VariableDeclaration(_, decls):
				addAll(decls);
			case VariableDeclarator(id, init):
				add(id);
				add(init);
			case IfStatement(t, c, a):
				add(t);
				add(c);
				add(a);
			case ForStatement(i, t, u, b):
				add(i);
				add(t);
				add(u);
				add(b);
			case ForInStatement(l, r, b):
				add(l);
				add(r);
				add(b);
			case ForOfStatement(l, r, b, _):
				add(l);
				add(r);
				add(b);
			case WhileStatement(t, b):
				add(t);
				add(b);
			case DoWhileStatement(b, t):
				add(b);
				add(t);
			case ReturnStatement(a):
				add(a);
			case ThrowStatement(a):
				add(a);
			case TryStatement(b, p, h, f):
				add(b);
				add(p);
				add(h);
				add(f);
			case SwitchStatement(d, cs):
				add(d);
				addAll(cs);
			case SwitchCase(t, cons):
				add(t);
				addAll(cons);
			case LabeledStatement(_, b):
				add(b);
			case FunctionDeclaration(fn):
				addFn(fn);
			case ClassDeclaration(c):
				addClass(c);
			case WithStatement(o, b):
				add(o);
				add(b);
			case ImportDeclaration(specs, _):
				addAll(specs);
			case ImportExpression(s, o):
				add(s);
				add(o);
			case ExportNamedDeclaration(d, specs, _):
				add(d);
				addAll(specs);
			case ExportDefaultDeclaration(d):
				add(d);

			case TemplateLiteral(_, _, exprs):
				addAll(exprs);
			case TaggedTemplateExpression(tag, q):
				add(tag);
				add(q);
			case ArrayExpression(els):
				addAll(els);
			case ObjectExpression(ps):
				addAll(ps);
			case Property(k, v, _, _, _, _):
				add(k);
				add(v);
			case SpreadElement(a):
				add(a);
			case RestElement(a):
				add(a);
			case ArrayPattern(els):
				addAll(els);
			case ObjectPattern(ps):
				addAll(ps);
			case AssignmentPattern(l, r):
				add(l);
				add(r);
			case UnaryExpression(_, a):
				add(a);
			case UpdateExpression(_, _, a):
				add(a);
			case BinaryExpression(_, l, r):
				add(l);
				add(r);
			case LogicalExpression(_, l, r):
				add(l);
				add(r);
			case AssignmentExpression(_, l, r):
				add(l);
				add(r);
			case ConditionalExpression(t, c, a):
				add(t);
				add(c);
				add(a);
			case CallExpression(c, args, _):
				add(c);
				addAll(args);
			case NewExpression(c, args):
				add(c);
				addAll(args);
			case MemberExpression(o, p, _, _):
				add(o);
				add(p);
			case SequenceExpression(es):
				addAll(es);
			case ArrowFunctionExpression(fn):
				addFn(fn);
			case FunctionExpression(fn):
				addFn(fn);
			case ClassExpression(c):
				addClass(c);
			case YieldExpression(a, _):
				add(a);
			case AwaitExpression(a):
				add(a);

			case MethodDefinition(k, _, _, _, fn):
				add(k);
				addFn(fn);
			case PropertyDefinition(k, _, _, v):
				add(k);
				add(v);
			case StaticBlock(b):
				add(b);

			// Leaves: identifiers, literals, keywords used as expressions, empty/debugger, meta properties...
			default:
				{}
		}
		return out;
	}

	/** Calls `visit` on `root` and every descendant, depth-first and in source order. */
	public static function walk(root:Node, visit:Node->Int->Void, depth:Int = 0):Void {
		visit(root, depth);
		for (child in children(root))
			walk(child, visit, depth + 1);
	}
}
