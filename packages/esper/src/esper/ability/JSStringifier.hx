package esper.ability;

import esper.ability.frontend.Ast.ClassData;
import esper.ability.frontend.Ast.FunctionData;
import esper.ability.frontend.Ast.Node;

/**
 * Turns an AST back into JavaScript source text.
 *
 * The esper does not keep the parentheses from the original source, so this printer
 * decides where parentheses are needed from operator precedence. Comments are not part
 * of the AST and are not printed.
 */
class JSStringifier {
	static var IDENT_NAME = ~/^[A-Za-z_$][A-Za-z0-9_$]*$/;

	var level = 0;
	var noIn = false;

	public function new() {}

	public static function stringify(program:Node):String {
		return new JSStringifier().program(program);
	}

	function pad():String {
		var s = "";
		for (k in 0...level)
			s += "  ";
		return s;
	}

	function program(n:Node):String {
		switch n.kind {
			case Program(body):
				var lines = [for (s in body) stmt(s)];
				return lines.join("\n") + "\n";
			default:
				return stmt(n) + "\n";
		}
	}

	/**
		The higher the value, the higher the priority.
	**/
	static function binPrec(op:String):Int {
		return switch op {
			case "??": 3;
			case "||": 4;
			case "&&": 5;
			case "|": 6;
			case "^": 7;
			case "&": 8;
			case "==", "!=", "===", "!==": 9;
			case "<", ">", "<=", ">=", "instanceof", "in": 10;
			case "<<", ">>", ">>>": 11;
			case "+", "-": 12;
			case "*", "/", "%": 13;
			case "**": 14;
			default: 0;
		};
	}

	/** 
		Same thing as binPrec but at the node level.
	 */
	static function prec(n:Node):Int {
		return switch n.kind {
			case SequenceExpression(_): 0;
			case ArrowFunctionExpression(_): 1;
			case YieldExpression(_, _): 1;
			case AssignmentExpression(_, _, _): 1;
			case ConditionalExpression(_, _, _): 2;
			case LogicalExpression(op, _, _): binPrec(op);
			case BinaryExpression(op, _, _): binPrec(op);
			case UnaryExpression(_, _): 15;
			case AwaitExpression(_): 15;
			case UpdateExpression(_, prefix, _): prefix ? 15 : 16;
			case MemberExpression(_, _, _, _): 17;
			case CallExpression(_, _, _): 17;
			case NewExpression(_, _): 17;
			case TaggedTemplateExpression(_, _): 17;
			case ImportExpression(_, _): 17;
			default: 18;
		};
	}

	/** Stringifies `n`, and adds parentheses if it has a lower precedence than `need`. */
	function expr(n:Node, need:Int):String {
		var s = raw(n);
		return prec(n) < need ? "(" + s + ")" : s;
	}

	function stmt(n:Node):String {
		switch n.kind {
			case ExpressionStatement(e):
				var exprText = expr(e, 0);
				return needsStatementParens(exprText) ? "(" + exprText + ");" : exprText + ";";

			case BlockStatement(body):
				return block(body);

			case EmptyStatement:
				return ";";

			// only here because of the spec.
			// Rhino likely ignores this.
			case DebuggerStatement:
				return "debugger;";

			case VariableDeclaration(_, _):
				return varDecl(n) + ";";

			case FunctionDeclaration(fn):
				return functionText(fn);

			case ClassDeclaration(cls):
				return classText(cls);

			case IfStatement(test, cons, alt):
				// A bare `if` as consequent would capture the `else`, so brace it.
				var consText = (alt != null && isIf(cons)) ? " " + block([cons]) : " " + stmt(cons);
				var ifText = "if (" + expr(test, 0) + ")" + consText;
				if (alt != null)
					ifText += " else " + stmt(alt);
				return ifText;

			case ForStatement(init, test, update, body):
				noIn = true;
				var initText = init == null ? "" : (isVarDecl(init) ? varDecl(init) : expr(init, 0));
				noIn = false;
				var testText = test == null ? "" : expr(test, 0);
				var updateText = update == null ? "" : expr(update, 0);
				return "for (" + initText + "; " + testText + "; " + updateText + ") " + stmt(body);

			case ForInStatement(left, right, body):
				return "for (" + loopHead(left) + " in " + expr(right, 0) + ") " + stmt(body);

			case ForOfStatement(left, right, body, isAwait):
				return "for" + (isAwait ? " await" : "") + " (" + loopHead(left) + " of " + expr(right, 1) + ") " + stmt(body);

			case WhileStatement(test, body):
				return "while (" + expr(test, 0) + ") " + stmt(body);

			case DoWhileStatement(body, test):
				return "do " + stmt(body) + " while (" + expr(test, 0) + ");";

			case ReturnStatement(arg):
				return "return" + (arg == null ? "" : " " + expr(arg, 0)) + ";";

			case BreakStatement(label):
				return "break" + (label == null ? "" : " " + label) + ";";

			case ContinueStatement(label):
				return "continue" + (label == null ? "" : " " + label) + ";";

			case ThrowStatement(arg):
				return "throw " + expr(arg, 0) + ";";

			case TryStatement(b, param, handler, finalizer):
				var tryText = "try " + blockOf(b);
				if (handler != null) {
					tryText += " catch" + (param == null ? "" : " (" + expr(param, 1) + ")") + " " + blockOf(handler);
				}
				if (finalizer != null)
					tryText += " finally " + blockOf(finalizer);
				return tryText;

			case SwitchStatement(disc, cases):
				level++;
				var caseTexts = [for (c in cases) switchCase(c)];
				level--;
				var inner = caseTexts.length == 0 ? "" : "\n" + caseTexts.join("\n") + "\n" + pad();
				return "switch (" + expr(disc, 0) + ") {" + inner + "}";

			case LabeledStatement(label, body):
				return label + ": " + stmt(body);

			case WithStatement(obj, body):
				return "with (" + expr(obj, 0) + ") " + stmt(body);

			case ImportDeclaration(specs, source):
				return importText(specs, source);

			case ExportNamedDeclaration(decl, specs, source):
				if (decl != null)
					return "export " + stmt(decl);
				var items = [for (s in specs) exportSpecText(s, source)];
				return "export { " + items.join(", ") + " }" + (source == null ? "" : " from " + quote(source)) + ";";

			case ExportDefaultDeclaration(decl):
				switch decl.kind {
					case FunctionDeclaration(fn): return "export default " + functionText(fn);
					case ClassDeclaration(cls): return "export default " + classText(cls);
					default: return "export default " + expr(decl, 1) + ";";
				}

			case ExportAllDeclaration(exported, source):
				return "export *" + (exported == null ? "" : " as " + moduleName(exported)) + " from " + quote(source) + ";";

			default:
				return expr(n, 0) + ";";
		}
	}

	function block(body:Array<Node>):String {
		if (body.length == 0)
			return "{}";
		level++;
		var lines = [for (s in body) pad() + stmt(s)];
		level--;
		return "{\n" + lines.join("\n") + "\n" + pad() + "}";
	}

	function blockOf(n:Node):String {
		return switch n.kind {
			case BlockStatement(body): block(body);
			default: stmt(n);
		};
	}

	function switchCase(c:Node):String {
		switch c.kind {
			case SwitchCase(test, cons):
				var head = test == null ? "default:" : "case " + expr(test, 0) + ":";
				level++;
				var lines = [for (s in cons) pad() + stmt(s)];
				level--;
				return pad() + head + (lines.length == 0 ? "" : "\n" + lines.join("\n"));
			default:
				return "";
		}
	}

	// Statements starting with these tokens would be parsed as declarations, so they need parentheses.
	static function needsStatementParens(s:String):Bool {
		return StringTools.startsWith(s, "{")
			|| StringTools.startsWith(s, "function")
			|| StringTools.startsWith(s, "async function")
			|| StringTools.startsWith(s, "class")
			|| StringTools.startsWith(s, "let [");
	}

	static function isIf(n:Node):Bool {
		return switch n.kind {
			case IfStatement(_, _, _): true;
			default: false;
		};
	}

	static function isVarDecl(n:Node):Bool {
		return switch n.kind {
			case VariableDeclaration(_, _): true;
			default: false;
		};
	}

	/** Head of a for-in / for-of loop: a declaration or an assignment target. */
	function loopHead(n:Node):String {
		return isVarDecl(n) ? varDecl(n) : expr(n, 17);
	}

	function varDecl(n:Node):String {
		return switch n.kind {
			case VariableDeclaration(kind, decls):
				kind + " " + [for (d in decls) declarator(d)].join(", ");
			default:
				expr(n, 0);
		};
	}

	function declarator(d:Node):String {
		return switch d.kind {
			case VariableDeclarator(id, init):
				expr(id, 1) + (init == null ? "" : " = " + expr(init, 1));
			default:
				expr(d, 1);
		};
	}

	function importText(specs:Array<Node>, source:String):String {
		if (specs.length == 0)
			return "import " + quote(source) + ";";

		var def:Null<String> = null;
		var ns:Null<String> = null;
		var named:Array<String> = [];
		for (s in specs) {
			switch s.kind {
				case ImportDefaultSpecifier(local):
					def = local;
				case ImportNamespaceSpecifier(local):
					ns = "* as " + local;
				case ImportSpecifier(imported, local):
					named.push(imported == local ? local : moduleName(imported) + " as " + local);
				default:
					continue;
			}
		}

		var bindings:Array<String> = [];
		if (def != null)
			bindings.push(def);
		if (ns != null)
			bindings.push(ns);
		if (named.length > 0)
			bindings.push("{ " + named.join(", ") + " }");
		return "import " + bindings.join(", ") + " from " + quote(source) + ";";
	}

	function exportSpecText(s:Node, source:Null<String>):String {
		return switch s.kind {
			case ExportSpecifier(local, exported):
				var l = source == null ? local : moduleName(local);
				local == exported ? l : l + " as " + moduleName(exported);
			default:
				"";
		};
	}

	// Module export names that are plain identifiers are printed bare, others as strings.
	static function moduleName(name:String):String {
		return IDENT_NAME.match(name) ? name : quote(name);
	}

	function params(ps:Array<Node>):String {
		return [for (p in ps) expr(p, 1)].join(", ");
	}

	static function fnOf(n:Node):Null<FunctionData> {
		return switch n.kind {
			case FunctionExpression(fn): fn;
			default: null;
		};
	}

	function functionText(fn:FunctionData):String {
		var head = (fn.isAsync ? "async " : "") + "function" + (fn.isGenerator ? "*" : "");
		if (fn.name != null)
			head += " " + fn.name;
		return head + "(" + params(fn.params) + ") " + blockOf(fn.body);
	}

	function classText(c:ClassData):String {
		var head = "class";
		if (c.name != null)
			head += " " + c.name;
		if (c.superClass != null)
			head += " extends " + expr(c.superClass, 17);
		return head + " " + classBody(c.members);
	}

	function classBody(members:Array<Node>):String {
		if (members.length == 0)
			return "{}";
		level++;
		var lines = [for (m in members) pad() + member(m)];
		level--;
		return "{\n" + lines.join("\n") + "\n" + pad() + "}";
	}

	function member(m:Node):String {
		switch m.kind {
			case MethodDefinition(key, computed, isStatic, kind, fn):
				var mods = isStatic ? "static " : "";
				if (kind == "get" || kind == "set") {
					mods += kind + " ";
				} else {
					mods += (fn.isAsync ? "async " : "") + (fn.isGenerator ? "*" : "");
				}
				return mods + keyText(key, computed) + "(" + params(fn.params) + ") " + blockOf(fn.body);

			case PropertyDefinition(key, computed, isStatic, value):
				return (isStatic ? "static " : "") + keyText(key, computed) + (value == null ? "" : " = " + expr(value, 1)) + ";";

			case StaticBlock(b):
				return "static " + blockOf(b);

			default:
				return expr(m, 1);
		}
	}

	function keyText(key:Node, computed:Bool):String {
		if (computed)
			return "[" + expr(key, 1) + "]";
		return switch key.kind {
			case Identifier(name): name;
			case PrivateIdentifier(name): "#" + name;
			case StringLiteral(s): quote(s);
			case NumberLiteral(v): numText(v);
			case BigIntLiteral(d): d + "n";
			default: expr(key, 1);
		};
	}

	// The raw text of an expression, without any outer parentheses.
	function raw(n:Node):String {
		switch n.kind {
			case Identifier(name):
				return name;
			case PrivateIdentifier(name):
				return "#" + name;
			case NumberLiteral(v):
				return numText(v);
			case BigIntLiteral(digits):
				return digits + "n";
			case StringLiteral(s):
				return quote(s);
			case BooleanLiteral(b):
				return b ? "true" : "false";
			case NullLiteral:
				return "null";
			case RegExpLiteral(pattern, flags):
				return "/" + pattern + "/" + flags;
			case TemplateLiteral(_, raws, exprs):
				return templateText(raws, exprs);
			case TaggedTemplateExpression(tag, quasi):
				return expr(tag, 17) + raw(quasi);
			case ThisExpression:
				return "this";
			case SuperExpression:
				return "super";
			case MetaProperty(meta, prop):
				return meta + "." + prop;

			case ArrayExpression(els):
				return arrayText(els);
			case ArrayPattern(els):
				return arrayText(els);
			case ObjectExpression(props):
				return objectText(props);
			case ObjectPattern(props):
				return objectText(props);

			case Property(key, value, computed, kind, shorthand, method):
				if (shorthand)
					return expr(value, 1);
				var methodFn = fnOf(value);
				if (method && methodFn != null) {
					var mods = (kind == "get" || kind == "set") ? kind + " " : (methodFn.isAsync ? "async " : "") + (methodFn.isGenerator ? "*" : "");
					return mods + keyText(key, computed) + "(" + params(methodFn.params) + ") " + blockOf(methodFn.body);
				}
				return keyText(key, computed) + ": " + expr(value, 1);

			case SpreadElement(arg):
				return "..." + expr(arg, 1);
			case RestElement(arg):
				return "..." + expr(arg, 1);
			case AssignmentPattern(left, right):
				return expr(left, 17) + " = " + expr(right, 1);

			case UnaryExpression(op, arg):
				var a = expr(arg, 15);
				var isWord = op == "typeof" || op == "void" || op == "delete";
				var sep = (isWord || StringTools.startsWith(a, op)) ? " " : "";
				return op + sep + a;

			case UpdateExpression(op, prefix, arg):
				return prefix ? op + expr(arg, 17) : expr(arg, 17) + op;

			case BinaryExpression(op, left, right):
				var p = binPrec(op);
				var ls = op == "**" ? expr(left, 16) : expr(left, p);
				var rs = op == "**" ? expr(right, 14) : expr(right, p + 1);
				var s = ls + " " + op + " " + rs;
				return (noIn && op == "in") ? "(" + s + ")" : s;

			case LogicalExpression(op, left, right):
				if (op == "??")
					return expr(left, 6) + " ?? " + expr(right, 6);
				var p2 = binPrec(op);
				return expr(left, p2) + " " + op + " " + expr(right, p2 + 1);

			case AssignmentExpression(op, left, right):
				return expr(left, 17) + " " + op + " " + expr(right, 1);

			case ConditionalExpression(test, cons, alt):
				return expr(test, 3) + " ? " + expr(cons, 1) + " : " + expr(alt, 1);

			case CallExpression(callee, args, optional):
				return expr(callee, 17) + (optional ? "?." : "") + "(" + argsText(args) + ")";

			case NewExpression(callee, args):
				return "new " + newCallee(callee) + "(" + argsText(args) + ")";

			case MemberExpression(object, property, computed, optional):
				var objText = expr(object, 17);
				if (!computed && isNumber(object))
					objText = "(" + objText + ")";
				if (computed)
					return objText + (optional ? "?.[" : "[") + expr(property, 0) + "]";
				return objText + (optional ? "?." : ".") + memberName(property);

			case SequenceExpression(exprs):
				return [for (e in exprs) expr(e, 1)].join(", ");

			case ArrowFunctionExpression(fn):
				var body:String;
				if (fn.isExpression) {
					var es = expr(fn.body, 1);
					body = StringTools.startsWith(es, "{") ? "(" + es + ")" : es;
				} else {
					body = blockOf(fn.body);
				}
				return (fn.isAsync ? "async " : "") + "(" + params(fn.params) + ") => " + body;

			case FunctionExpression(fn):
				return functionText(fn);
			case ClassExpression(cls):
				return classText(cls);

			case YieldExpression(arg, delegate):
				return "yield" + (delegate ? "*" : "") + (arg == null ? "" : " " + expr(arg, 1));
			case AwaitExpression(arg):
				return "await " + expr(arg, 15);

			case ImportExpression(source, options):
				return "import(" + expr(source, 1) + (options == null ? "" : ", " + expr(options, 1)) + ")";

			default:
				throw new haxe.Exception("Codegen: cannot print node " + Type.enumConstructor(n.kind));
		}
	}

	function argsText(args:Array<Node>):String {
		return [for (a in args) expr(a, 1)].join(", ");
	}

	function newCallee(n:Node):String {
		return hasCall(n) ? "(" + raw(n) + ")" : expr(n, 17);
	}

	function hasCall(n:Node):Bool {
		return switch n.kind {
			case CallExpression(_, _, _): true;
			case MemberExpression(object, _, _, _): hasCall(object);
			default: false;
		};
	}

	function isNumber(n:Node):Bool {
		return switch n.kind {
			case NumberLiteral(_): true;
			default: false;
		};
	}

	function memberName(n:Node):String {
		return switch n.kind {
			case Identifier(name): name;
			case PrivateIdentifier(name): "#" + name;
			default: expr(n, 0);
		};
	}

	function arrayText(els:Array<Null<Node>>):String {
		var parts = [for (e in els) e == null ? "" : expr(e, 1)];
		var s = parts.join(", ");

		if (els.length > 0 && els[els.length - 1] == null)
			s += ",";
		return "[" + s + "]";
	}

	function objectText(props:Array<Node>):String {
		if (props.length == 0)
			return "{}";
		return "{ " + [for (p in props) expr(p, 1)].join(", ") + " }";
	}

	function templateText(raws:Array<String>, exprs:Array<Node>):String {
		var s = "`" + raws[0];
		for (k in 0...exprs.length) {
			s += "${" + expr(exprs[k], 0) + "}" + raws[k + 1];
		}
		return s + "`";
	}

	static function numText(v:Float):String {
		return Std.string(v);
	}

	static function quote(s:String):String {
		var b = new StringBuf();
		b.add("\"");
		for (i in 0...s.length) {
			var c = s.charAt(i);
			switch c {
				case "\"":
					b.add("\\\"");
				case "\\":
					b.add("\\\\");
				case "\n":
					b.add("\\n");
				case "\r":
					b.add("\\r");
				case "\t":
					b.add("\\t");
				case "\u2028":
					b.add("\\u2028");
				case "\u2029":
					b.add("\\u2029");
				default:
					var code = c.charCodeAt(0) ?? 0;
					if (code < 0x20 || code == 0x7F) {
						b.add("\\u" + StringTools.hex(code, 4));
					} else {
						b.add(c);
					}
			}
		}
		b.add("\"");
		return b.toString();
	}
}
