package esper;

import esper.Ast.Node;
import esper.Ast.NodeKind;
import esper.Ast.NodeKind.*;
import esper.Ast.FunctionData;
import esper.Ast.ClassData;
import esper.Token.Token;
import esper.Token.TokenType;
import esper.Token.TokenType.*;

class Parser {
	static final ASSIGN_OPS:Array<String> = [
		"=", "+=", "-=", "*=", "/=", "%=", "**=", "<<=", ">>=", ">>>=", "&=", "|=", "^=", "&&=", "||=", "??="
	];

	final tokens:Array<Token>;
	final isModule:Bool;
	var i = 0;
	var inAsync = false;
	var inGenerator = false;

	/** When true, the `in` operator is not consumed (used for `for (init in ...)` heads). */
	var noIn = false;

	public function new(tokens:Array<Token>, isModule:Bool = false) {
		this.tokens = tokens;
		this.isModule = isModule;
	}

	/** Parses a script (default) or a module and returns the Program node. */
	public static function parse(source:String, isModule:Bool = false):Node {
		var tokens = new Lexer(source).tokenize();
		return new Parser(tokens, isModule).parseProgram();
	}

	// =====================================================================
	// Token helpers
	// =====================================================================

	function peek(o:Int = 0):Token {
		var k = i + o;
		return tokens[k < tokens.length ? k : tokens.length - 1];
	}

	function next():Token {
		var t = tokens[i];
		if (i < tokens.length - 1)
			i++;
		return t;
	}

	function isP(v:String, o:Int = 0):Bool {
		var t = peek(o);
		return t.type == TPunct && t.value == v;
	}

	function isK(v:String, o:Int = 0):Bool {
		var t = peek(o);
		return t.type == TKeyword && t.value == v;
	}

	function isId(v:String, o:Int = 0):Bool {
		var t = peek(o);
		return t.type == TIdent && t.value == v;
	}

	function eatP(v:String):Bool {
		if (isP(v)) {
			next();
			return true;
		}
		return false;
	}

	function expectP(v:String):Token {
		if (!isP(v))
			fail('Expected "$v"');
		return next();
	}

	function expectK(v:String):Token {
		if (!isK(v))
			fail('Expected "$v"');
		return next();
	}

	function fail(msg:String, ?at:Token):Dynamic {
		var t = at != null ? at : peek();
		throw new ParseError('$msg, found "${t.value}"', t.line, t.col);
	}

	function mk(kind:NodeKind, t:Token):Node {
		return {kind: kind, line: t.line, col: t.col};
	}

	/** Automatic semicolon insertion. */
	function consumeSemi():Void {
		if (eatP(";"))
			return;
		var t = peek();
		if (isP("}") || t.type == TEOF || t.newlineBefore)
			return;
		fail('Expected ";"');
	}

	function isBindingStart(o:Int):Bool {
		return peek(o).type == TIdent || isP("[", o) || isP("{", o);
	}

	static function keyName(k:Node):Null<String> {
		return switch k.kind {
			case Identifier(n): n;
			case StringLiteral(s): s;
			default: null;
		};
	}

	// =====================================================================
	// Program and statements
	// =====================================================================

	public function parseProgram():Node {
		var start = peek();
		inAsync = isModule; // top-level await is allowed in modules only
		var body:Array<Node> = [];
		while (peek().type != TEOF)
			body.push(parseStatement());
		return mk(Program(body), start);
	}

	function parseStatement():Node {
		var t = peek();
		if (t.type == TPunct && t.value == "{")
			return parseBlock();
		if (t.type == TPunct && t.value == ";") {
			next();
			return mk(EmptyStatement, t);
		}
		if (t.type == TKeyword) {
			var s = parseKeywordStatement(t);
			if (s != null)
				return s;
		}
		if (t.type == TIdent) {
			if (t.value == "let" && isBindingStart(1))
				return parseVarStatement();
			if (t.value == "async" && isK("function", 1) && !peek(1).newlineBefore)
				return parseFunction(true, true);
			if (isP(":", 1)) {
				next();
				next();
				return mk(LabeledStatement(t.value, parseStatement()), t);
			}
		}
		var e = parseExpression();
		consumeSemi();
		return mk(ExpressionStatement(e), t);
	}

	function parseKeywordStatement(t:Token):Null<Node> {
		switch t.value {
			case "var", "const":
				return parseVarStatement();
			case "function":
				return parseFunction(false, true);
			case "class":
				return parseClass(true);
			case "if":
				next();
				expectP("(");
				var ifTest = parseExpression();
				expectP(")");
				var cons = parseStatement();
				var alt:Null<Node> = null;
				if (isK("else")) {
					next();
					alt = parseStatement();
				}
				return mk(IfStatement(ifTest, cons, alt), t);
			case "for":
				return parseFor(t);
			case "while":
				next();
				expectP("(");
				var wTest = parseExpression();
				expectP(")");
				return mk(WhileStatement(wTest, parseStatement()), t);
			case "do":
				next();
				var dBody = parseStatement();
				expectK("while");
				expectP("(");
				var dTest = parseExpression();
				expectP(")");
				eatP(";");
				return mk(DoWhileStatement(dBody, dTest), t);
			case "return":
				next();
				var arg:Null<Node> = null;
				if (!(isP(";") || isP("}") || peek().type == TEOF || peek().newlineBefore))
					arg = parseExpression();
				consumeSemi();
				return mk(ReturnStatement(arg), t);
			case "break", "continue":
				next();
				var label:Null<String> = null;
				if (peek().type == TIdent && !peek().newlineBefore)
					label = next().value;
				consumeSemi();
				return mk(t.value == "break" ? BreakStatement(label) : ContinueStatement(label), t);
			case "throw":
				next();
				if (peek().newlineBefore)
					fail("Illegal newline after throw");
				var thrown = parseExpression();
				consumeSemi();
				return mk(ThrowStatement(thrown), t);
			case "try":
				return parseTry(t);
			case "switch":
				return parseSwitch(t);
			case "debugger":
				next();
				consumeSemi();
				return mk(DebuggerStatement, t);
			case "import":
				// import(...) and import.meta are expressions, handled in parsePrimary
				if (isP("(", 1) || isP(".", 1))
					return null;
				return parseImportDeclaration(t);
			case "export":
				return parseExportDeclaration(t);
			case "with":
				next();
				expectP("(");
				var withObject = parseExpression();
				expectP(")");
				return mk(WithStatement(withObject, parseStatement()), t);
			default:
				return null;
		}
	}

	function parseBlock():Node {
		var t = expectP("{");
		var body:Array<Node> = [];
		while (!isP("}"))
			body.push(parseStatement());
		next();
		return mk(BlockStatement(body), t);
	}

	function parseVarStatement():Node {
		var kt = next();
		var decls = parseVarDeclarations();
		consumeSemi();
		return mk(VariableDeclaration(kt.value, decls), kt);
	}

	function parseVarDeclarations():Array<Node> {
		var list:Array<Node> = [];
		do {
			var t = peek();
			var id = parseBindingTarget();
			var init:Null<Node> = eatP("=") ? parseAssign() : null;
			list.push(mk(VariableDeclarator(id, init), t));
		} while (eatP(","));
		return list;
	}

	function parseFor(t:Token):Node {
		next(); // for
		var isAwait = false;
		if (isId("await")) {
			next();
			isAwait = true;
		}
		expectP("(");

		var init:Null<Node> = null;
		noIn = true;
		if (!isP(";")) {
			if (isK("var") || isK("const") || (isId("let") && isBindingStart(1))) {
				var kt = next();
				init = mk(VariableDeclaration(kt.value, parseVarDeclarations()), kt);
			} else {
				init = parseExpression();
			}
		}
		noIn = false;

		if (init != null && (isId("of") || isK("in"))) {
			var isOf = isId("of");
			next();
			var right = isOf ? parseAssign() : parseExpression();
			expectP(")");
			var loopBody = parseStatement();
			return isOf ? mk(ForOfStatement(init, right, loopBody, isAwait), t) : mk(ForInStatement(init, right, loopBody), t);
		}

		expectP(";");
		var test:Null<Node> = isP(";") ? null : parseExpression();
		expectP(";");
		var update:Null<Node> = isP(")") ? null : parseExpression();
		expectP(")");
		var forBody = parseStatement();
		return mk(ForStatement(init, test, update, forBody), t);
	}

	function parseTry(t:Token):Node {
		next(); // try
		var block = parseBlock();
		var param:Null<Node> = null;
		var handler:Null<Node> = null;
		var finalizer:Null<Node> = null;
		if (isK("catch")) {
			next();
			if (eatP("(")) {
				param = parseBindingTarget();
				expectP(")");
			}
			handler = parseBlock();
		}
		if (isK("finally")) {
			next();
			finalizer = parseBlock();
		}
		if (handler == null && finalizer == null)
			fail("Missing catch or finally after try");
		return mk(TryStatement(block, param, handler, finalizer), t);
	}

	function parseSwitch(t:Token):Node {
		next(); // switch
		expectP("(");
		var disc = parseExpression();
		expectP(")");
		expectP("{");
		var cases:Array<Node> = [];
		while (!isP("}")) {
			var ct = peek();
			var caseTest:Null<Node> = null;
			if (isK("case")) {
				next();
				caseTest = parseExpression();
			} else if (isK("default")) {
				next();
			} else {
				fail('Expected "case" or "default"');
			}
			expectP(":");
			var consequent:Array<Node> = [];
			while (!isP("}") && !isK("case") && !isK("default"))
				consequent.push(parseStatement());
			cases.push(mk(SwitchCase(caseTest, consequent), ct));
		}
		next();
		return mk(SwitchStatement(disc, cases), t);
	}

	// =====================================================================
	// Functions and classes
	// =====================================================================

	function parseFunction(isAsync:Bool, isDecl:Bool, allowAnon:Bool = false):Node {
		var t = peek();
		if (isAsync)
			next(); // async
		expectK("function");
		var isGen = eatP("*");
		var name:Null<String> = null;
		if (peek().type == TIdent) {
			name = next().value;
		} else if (isDecl && !allowAnon) {
			fail("Function declaration requires a name");
		}
		var fn = parseFunctionRest(name, isAsync, isGen);
		return mk(isDecl ? FunctionDeclaration(fn) : FunctionExpression(fn), t);
	}

	/** Parses "(params) { body }" and returns the function data. */
	function parseFunctionRest(name:Null<String>, isAsync:Bool, isGen:Bool):FunctionData {
		var savedAsync = inAsync;
		var savedGen = inGenerator;
		var savedNoIn = noIn;
		inAsync = isAsync;
		inGenerator = isGen;
		noIn = false;

		expectP("(");
		var params = parseParams();
		var body = parseBlock();

		inAsync = savedAsync;
		inGenerator = savedGen;
		noIn = savedNoIn;
		return {
			name: name,
			params: params,
			body: body,
			isAsync: isAsync,
			isGenerator: isGen,
			isArrow: false,
			isExpression: false
		};
	}

	/** Parses parameters; the opening '(' has already been consumed. Consumes the closing ')'. */
	function parseParams():Array<Node> {
		var ps:Array<Node> = [];
		while (!isP(")")) {
			var pt = peek();
			if (eatP("...")) {
				ps.push(mk(RestElement(parseBindingTarget()), pt));
			} else {
				ps.push(parseBindingElement());
			}
			if (!isP(")"))
				expectP(",");
		}
		next();
		return ps;
	}

	function parseClass(isDecl:Bool, allowAnon:Bool = false):Node {
		var t = next(); // class
		var name:Null<String> = null;
		if (peek().type == TIdent) {
			name = next().value;
		} else if (isDecl && !allowAnon) {
			fail("Class declaration requires a name");
		}
		var superClass:Null<Node> = null;
		if (isK("extends")) {
			next();
			superClass = parseLeftHandSide();
		}
		expectP("{");
		var members:Array<Node> = [];
		while (!isP("}")) {
			if (eatP(";"))
				continue;
			members.push(parseClassMember());
		}
		next(); // }
		var data:ClassData = {name: name, superClass: superClass, members: members};
		return mk(isDecl ? ClassDeclaration(data) : ClassExpression(data), t);
	}

	function parseClassMember():Node {
		var t = peek();

		var isStatic = false;
		if (isId("static") && !isP("(", 1) && !isP("=", 1) && !isP(";", 1) && !isP("}", 1)) {
			next();
			isStatic = true;
			if (isP("{"))
				return mk(StaticBlock(parseBlock()), t);
		}

		var isAsync = false;
		if (isId("async") && !isP("(", 1) && !isP("=", 1) && !isP(";", 1) && !isP("}", 1) && !peek(1).newlineBefore) {
			next();
			isAsync = true;
		}

		var isGen = eatP("*");

		var kind = "method";
		if ((isId("get") || isId("set")) && !isP("(", 1) && !isP("=", 1) && !isP(";", 1) && !isP("}", 1)) {
			kind = next().value;
		}

		var computed = eatP("[");
		var key:Node;
		if (computed) {
			key = parseAssign();
			expectP("]");
		} else {
			key = parsePropertyName();
		}

		if (isP("(")) {
			var isCtor = !isStatic && !computed && kind == "method" && keyName(key) == "constructor";
			var fn = parseFunctionRest(null, isAsync, isGen);
			return mk(MethodDefinition(key, computed, isStatic, isCtor ? "constructor" : kind, fn), t);
		}

		// Field definition
		var value:Null<Node> = null;
		if (eatP("="))
			value = parseAssign();
		consumeSemi();
		return mk(PropertyDefinition(key, computed, isStatic, value), t);
	}

	// =====================================================================
	// Binding patterns (declarations and parameters)
	// =====================================================================

	function parseBindingTarget():Node {
		var t = peek();
		if (isP("["))
			return parseArrayPattern();
		if (isP("{"))
			return parseObjectPattern();
		if (t.type == TIdent) {
			next();
			return mk(Identifier(t.value), t);
		}
		return fail("Expected a binding identifier or pattern");
	}

	/** A binding target with an optional default value. */
	function parseBindingElement():Node {
		var t = peek();
		var target = parseBindingTarget();
		if (eatP("="))
			return mk(AssignmentPattern(target, parseAssign()), t);
		return target;
	}

	function parseArrayPattern():Node {
		var t = next(); // [
		var els:Array<Null<Node>> = [];
		while (!isP("]")) {
			if (eatP(",")) {
				els.push(null);
				continue;
			}
			if (isP("...")) {
				var rt = next();
				els.push(mk(RestElement(parseBindingTarget()), rt));
			} else {
				els.push(parseBindingElement());
			}
			if (!isP("]"))
				expectP(",");
		}
		next();
		return mk(ArrayPattern(els), t);
	}

	function parseObjectPattern():Node {
		var t = next(); // {
		var props:Array<Node> = [];
		while (!isP("}")) {
			var pt = peek();
			if (eatP("...")) {
				props.push(mk(RestElement(parseBindingTarget()), pt));
			} else {
				var computed = eatP("[");
				var key:Node;
				if (computed) {
					key = parseAssign();
					expectP("]");
				} else {
					key = parsePropertyName();
				}
				if (eatP(":")) {
					props.push(mk(Property(key, parseBindingElement(), computed, "init", false, false), pt));
				} else {
					var name = keyName(key);
					if (name == null || computed)
						fail("Invalid shorthand property in pattern", pt);
					var value:Node = mk(Identifier(name), pt);
					if (eatP("="))
						value = mk(AssignmentPattern(value, parseAssign()), pt);
					props.push(mk(Property(key, value, false, "init", true, false), pt));
				}
			}
			if (!isP("}"))
				expectP(",");
		}
		next();
		return mk(ObjectPattern(props), t);
	}

	// =====================================================================
	// Expressions
	// =====================================================================

	function parseExpression():Node {
		var t = peek();
		var e = parseAssign();
		if (!isP(","))
			return e;
		var list:Array<Node> = [e];
		while (eatP(","))
			list.push(parseAssign());
		return mk(SequenceExpression(list), t);
	}

	/** 0 = not an arrow, 1 = arrow, 2 = async arrow. */
	function arrowKind():Int {
		if (peek().type == TIdent && isP("=>", 1))
			return 1;
		if (isP("(") && isArrowAhead(i))
			return 1;
		if (isId("async") && !peek(1).newlineBefore) {
			if (peek(1).type == TIdent && isP("=>", 2))
				return 2;
			if (isP("(", 1) && isArrowAhead(i + 1))
				return 2;
		}
		return 0;
	}

	/** Given the index of a "(" token, checks whether its matching ")" is followed by "=>". */
	function isArrowAhead(k:Int):Bool {
		var depth = 0;
		var j = k;
		while (j < tokens.length) {
			var tk = tokens[j];
			if (tk.type == TEOF)
				return false;
			if (tk.type == TPunct) {
				if (tk.value == "(" || tk.value == "[" || tk.value == "{") {
					depth++;
				} else if (tk.value == ")" || tk.value == "]" || tk.value == "}") {
					depth--;
					if (depth == 0) {
						var after = j + 1 < tokens.length ? tokens[j + 1] : null;
						return after != null && after.type == TPunct && after.value == "=>";
					}
				}
			}
			j++;
		}
		return false;
	}

	function parseAssign():Node {
		var t = peek();
		var ak = arrowKind();
		if (ak > 0)
			return parseArrow(ak == 2);
		if (isId("yield") && inGenerator)
			return parseYield();

		var left = parseConditional();
		var op = peek();
		if (op.type == TPunct && ASSIGN_OPS.indexOf(op.value) >= 0) {
			next();
			var right = parseAssign();
			return mk(AssignmentExpression(op.value, left, right), t);
		}
		return left;
	}

	function parseArrow(isAsync:Bool):Node {
		var t = peek();
		if (isAsync)
			next(); // async

		var params:Array<Node>;
		if (peek().type == TIdent) {
			var id = next();
			params = [mk(Identifier(id.value), id)];
		} else {
			expectP("(");
			params = parseParams();
		}
		expectP("=>");

		var savedAsync = inAsync;
		var savedGen = inGenerator;
		var savedNoIn = noIn;
		inAsync = isAsync;
		inGenerator = false;

		var body:Node;
		var isExpr:Bool;
		if (isP("{")) {
			body = parseBlock();
			isExpr = false;
		} else {
			body = parseAssign();
			isExpr = true;
		}

		inAsync = savedAsync;
		inGenerator = savedGen;
		noIn = savedNoIn;

		var fn:FunctionData = {
			name: null,
			params: params,
			body: body,
			isAsync: isAsync,
			isGenerator: false,
			isArrow: true,
			isExpression: isExpr
		};
		return mk(ArrowFunctionExpression(fn), t);
	}

	function parseYield():Node {
		var t = next(); // yield
		var delegate = false;
		var arg:Null<Node> = null;
		if (!peek().newlineBefore) {
			if (eatP("*")) {
				delegate = true;
				arg = parseAssign();
			} else if (!endsExpression()) {
				arg = parseAssign();
			}
		}
		return mk(YieldExpression(arg, delegate), t);
	}

	function endsExpression():Bool {
		var t = peek();
		if (t.type == TEOF)
			return true;
		if (t.type == TPunct)
			return [")", "]", "}", ",", ";", ":"].indexOf(t.value) >= 0;
		return false;
	}

	function parseConditional():Node {
		var t = peek();
		var test = parseBinary(1);
		if (!isP("?"))
			return test;
		next();
		var savedNoIn = noIn;
		noIn = false;
		var cons = parseAssign();
		noIn = savedNoIn;
		expectP(":");
		var alt = parseAssign();
		return mk(ConditionalExpression(test, cons, alt), t);
	}

	function binPrec(t:Token):Int {
		if (t.type == TKeyword) {
			if (t.value == "instanceof")
				return 8;
			if (t.value == "in" && !noIn)
				return 8;
			return -1;
		}
		if (t.type != TPunct)
			return -1;
		return switch t.value {
			case "??": 1;
			case "||": 2;
			case "&&": 3;
			case "|": 4;
			case "^": 5;
			case "&": 6;
			case "==", "!=", "===", "!==": 7;
			case "<", ">", "<=", ">=": 8;
			case "<<", ">>", ">>>": 9;
			case "+", "-": 10;
			case "*", "/", "%": 11;
			case "**": 12;
			default: -1;
		};
	}

	/** Precedence climbing for all binary and logical operators. */
	function parseBinary(minPrec:Int):Node {
		var t = peek();
		var left = parseUnary();
		while (true) {
			var op = peek();
			var prec = binPrec(op);
			if (prec < 0 || prec < minPrec)
				break;
			next();
			// ** is right-associative, everything else is left-associative
			var right = op.value == "**" ? parseBinary(prec) : parseBinary(prec + 1);
			var isLogical = op.value == "&&" || op.value == "||" || op.value == "??";
			left = isLogical ? mk(LogicalExpression(op.value, left, right), t) : mk(BinaryExpression(op.value, left, right), t);
		}
		return left;
	}

	static function isUnaryOperator(t:Token):Bool {
		return (t.type == TPunct && ["!", "~", "+", "-"].indexOf(t.value) >= 0)
			|| (t.type == TKeyword && ["typeof", "void", "delete"].indexOf(t.value) >= 0);
	}

	function parseUnary():Node {
		var t = peek();
		if (isUnaryOperator(t)) {
			next();
			return mk(UnaryExpression(t.value, parseUnary()), t);
		}
		if (isP("++") || isP("--")) {
			next();
			return mk(UpdateExpression(t.value, true, parseUnary()), t);
		}
		if (inAsync && isId("await")) {
			next();
			return mk(AwaitExpression(parseUnary()), t);
		}
		return parsePostfix();
	}

	function parsePostfix():Node {
		var t = peek();
		var e = parseLeftHandSide();
		var n = peek();
		if (n.type == TPunct && (n.value == "++" || n.value == "--") && !n.newlineBefore) {
			next();
			return mk(UpdateExpression(n.value, false, e), t);
		}
		return e;
	}

	function parseLeftHandSide():Node {
		var t = peek();
		var base = isK("new") ? parseNew() : parsePrimary();
		return parseCallTail(base, t, true);
	}

	function parseNew():Node {
		var t = next(); // new
		if (eatP(".")) {
			var prop = next(); // new.target
			return mk(MetaProperty(t.value, prop.value), t);
		}
		var callee:Node = isK("new") ? parseNew() : parsePrimary();
		callee = parseCallTail(callee, t, false);
		var args:Array<Node> = isP("(") ? parseArguments() : [];
		return mk(NewExpression(callee, args), t);
	}

	/** Member access, optional chaining, calls, and tagged templates. */
	function parseCallTail(base:Node, t:Token, allowCall:Bool):Node {
		var e = base;
		while (true) {
			if (eatP(".")) {
				e = mk(MemberExpression(e, parseMemberName(), false, false), t);
			} else if (isP("?.")) {
				next();
				if (isP("(") && allowCall) {
					e = mk(CallExpression(e, parseArguments(), true), t);
				} else if (eatP("[")) {
					var keyExpr = parseExpression();
					expectP("]");
					e = mk(MemberExpression(e, keyExpr, true, true), t);
				} else {
					e = mk(MemberExpression(e, parseMemberName(), false, true), t);
				}
			} else if (isP("[")) {
				next();
				var propExpr = parseExpression();
				expectP("]");
				e = mk(MemberExpression(e, propExpr, true, false), t);
			} else if (allowCall && isP("(")) {
				e = mk(CallExpression(e, parseArguments(), false), t);
			} else if (peek().type == TTemplate && peek().head) {
				e = mk(TaggedTemplateExpression(e, parseTemplate()), t);
			} else {
				break;
			}
		}
		return e;
	}

	function parseMemberName():Node {
		var t = next();
		if (t.type == TPrivate)
			return mk(PrivateIdentifier(t.value), t);
		if (t.type == TIdent || t.type == TKeyword)
			return mk(Identifier(t.value), t);
		return fail("Expected a property name", t);
	}

	/** Parses "( args )". Consumes both parentheses. */
	function parseArguments():Array<Node> {
		expectP("(");
		var args:Array<Node> = [];
		while (!isP(")")) {
			var at = peek();
			if (eatP("...")) {
				args.push(mk(SpreadElement(parseAssign()), at));
			} else {
				args.push(parseAssign());
			}
			if (!isP(")"))
				expectP(",");
		}
		next();
		return args;
	}

	function parsePrimary():Node {
		var t = peek();
		switch t.type {
			case TIdent:
				if (t.value == "async" && isK("function", 1) && !peek(1).newlineBefore) {
					return parseFunction(true, false);
				}
				next();
				return mk(Identifier(t.value), t);

			case TPrivate:
				// `#x in obj`
				next();
				return mk(PrivateIdentifier(t.value), t);

			case TNumber:
				next();
				return mk(NumberLiteral(t.numValue), t);

			case TBigInt:
				next();
				return mk(BigIntLiteral(t.value), t);

			case TString:
				next();
				return mk(StringLiteral(t.value), t);

			case TTemplate:
				return parseTemplate();

			case TRegExp:
				next();
				return mk(RegExpLiteral(t.value, t.flags), t);

			case TKeyword:
				switch t.value {
					case "this":
						next();
						return mk(ThisExpression, t);
					case "super":
						next();
						return mk(SuperExpression, t);
					case "null":
						next();
						return mk(NullLiteral, t);
					case "true":
						next();
						return mk(BooleanLiteral(true), t);
					case "false":
						next();
						return mk(BooleanLiteral(false), t);
					case "import":
						return parseImportExpr(t);
					case "function":
						return parseFunction(false, false);
					case "class":
						return parseClass(false);
					default:
						return fail("Unexpected keyword", t);
				}

			case TPunct:
				switch t.value {
					case "(":
						next();
						var savedNoIn = noIn;
						noIn = false;
						var inner = parseExpression();
						noIn = savedNoIn;
						expectP(")");
						return inner;
					case "[":
						return parseArrayLiteral();
					case "{":
						return parseObjectLiteral();
					default:
						return fail("Unexpected token", t);
				}

			default:
				return fail("Unexpected end of input", t);
		}
	}

	// =====================================================================
	// Modules: import/export, dynamic import(), import.meta
	// =====================================================================

	function requireModule(t:Token):Void {
		if (!isModule)
			fail("import/export and import.meta are only allowed in modules", t);
	}

	function expectId(v:String):Token {
		if (!isId(v))
			fail('Expected "$v"');
		return next();
	}

	function expectIdentName():String {
		if (peek().type != TIdent)
			fail("Expected an identifier");
		return next().value;
	}

	function expectString():String {
		if (peek().type != TString)
			fail("Expected a string literal");
		return next().value;
	}

	/** Names in import/export specifier lists may be identifiers, keywords, or strings. */
	function parseModuleExportName():String {
		var t = peek();
		if (t.type == TIdent || t.type == TKeyword || t.type == TString) {
			next();
			return t.value;
		}
		return fail("Expected a module export name");
	}

	static function isDeclarationKind(k:NodeKind):Bool {
		return switch k {
			case VariableDeclaration(_, _), FunctionDeclaration(_), ClassDeclaration(_): true;
			default: false;
		};
	}

	/**
	 * import x from 'm';
	 * import x, { a, b as c } from 'm';
	 * import * as ns from 'm';
	 * import { default as d } from 'm';
	 * import 'm';
	 */
	function parseImportDeclaration(t:Token):Node {
		requireModule(t);
		next(); // import
		var specs:Array<Node> = [];

		if (peek().type == TString) { // side-effect import
			var bare = next().value;
			consumeSemi();
			return mk(ImportDeclaration(specs, bare), t);
		}

		if (peek().type == TIdent) { // default binding
			var defTok = next();
			specs.push(mk(ImportDefaultSpecifier(defTok.value), defTok));
			eatP(",");
		}

		if (isP("*")) { // namespace binding
			var starTok = next();
			expectId("as");
			specs.push(mk(ImportNamespaceSpecifier(expectIdentName()), starTok));
		} else if (isP("{")) { // named bindings
			next();
			while (!isP("}")) {
				var st = peek();
				var imported = parseModuleExportName();
				var local = imported;
				if (isId("as")) {
					next();
					local = expectIdentName();
				}
				specs.push(mk(ImportSpecifier(imported, local), st));
				if (!isP("}"))
					expectP(",");
			}
			next();
		}

		expectId("from");
		var source = expectString();
		consumeSemi();
		return mk(ImportDeclaration(specs, source), t);
	}

	/**
	 * export default <expr>;
	 * export default function/class [name] ...
	 * export { a, b as c } [from 'm'];
	 * export * [as ns] from 'm';
	 * export <var | let | const | function | class | async function declaration>
	 */
	function parseExportDeclaration(t:Token):Node {
		requireModule(t);
		next(); // export

		if (isP("*")) {
			next();
			var exported:Null<String> = null;
			if (isId("as")) {
				next();
				exported = parseModuleExportName();
			}
			expectId("from");
			var fromSource = expectString();
			consumeSemi();
			return mk(ExportAllDeclaration(exported, fromSource), t);
		}

		if (isK("default")) {
			next();
			var decl:Node;
			if (isK("function") || (isId("async") && isK("function", 1) && !peek(1).newlineBefore)) {
				decl = parseFunction(isId("async"), true, true);
			} else if (isK("class")) {
				decl = parseClass(true, true);
			} else {
				decl = parseAssign();
				consumeSemi();
			}
			return mk(ExportDefaultDeclaration(decl), t);
		}

		if (isP("{")) {
			next();
			var specs:Array<Node> = [];
			while (!isP("}")) {
				var st = peek();
				var local = parseModuleExportName();
				var exportedName = local;
				if (isId("as")) {
					next();
					exportedName = parseModuleExportName();
				}
				specs.push(mk(ExportSpecifier(local, exportedName), st));
				if (!isP("}"))
					expectP(",");
			}
			next();
			var reexportFrom:Null<String> = null;
			if (isId("from")) {
				next();
				reexportFrom = expectString();
			}
			consumeSemi();
			return mk(ExportNamedDeclaration(null, specs, reexportFrom), t);
		}

		// export <declaration>
		var inner = parseStatement();
		if (!isDeclarationKind(inner.kind))
			fail("Invalid export declaration", t);
		return mk(ExportNamedDeclaration(inner, [], null), t);
	}

	/** import(source [, options]) and import.meta. Both start at the `import` token. */
	function parseImportExpr(t:Token):Node {
		next(); // import
		if (eatP(".")) {
			if (!isId("meta"))
				fail('Expected "meta"');
			requireModule(t);
			next();
			return mk(MetaProperty("import", "meta"), t);
		}
		expectP("(");
		var source = parseAssign();
		var options:Null<Node> = null;
		if (eatP(",") && !isP(")")) {
			options = parseAssign();
			eatP(",");
		}
		expectP(")");
		return mk(ImportExpression(source, options), t);
	}

	function parseArrayLiteral():Node {
		var t = next(); // [
		var els:Array<Null<Node>> = [];
		while (!isP("]")) {
			if (eatP(",")) {
				els.push(null);
				continue;
			}
			var et = peek();
			if (eatP("...")) {
				els.push(mk(SpreadElement(parseAssign()), et));
			} else {
				els.push(parseAssign());
			}
			if (!isP("]"))
				expectP(",");
		}
		next();
		return mk(ArrayExpression(els), t);
	}

	function parseObjectLiteral():Node {
		var t = next(); // {
		var props:Array<Node> = [];
		while (!isP("}")) {
			props.push(parseObjectMember());
			if (!isP("}"))
				expectP(",");
		}
		next();
		return mk(ObjectExpression(props), t);
	}

	function parseObjectMember():Node {
		var t = peek();
		if (eatP("..."))
			return mk(SpreadElement(parseAssign()), t);

		// Modifiers are only modifiers when a property name follows them.
		var nameFollows = !isP(",", 1) && !isP(":", 1) && !isP("(", 1) && !isP("}", 1) && !isP("=", 1);

		var isAsync = false;
		if (isId("async") && nameFollows) {
			next();
			isAsync = true;
		}
		var isGen = eatP("*");

		var kind = "init";
		if ((isId("get") || isId("set")) && nameFollows) {
			kind = next().value;
		}

		var computed = eatP("[");
		var key:Node;
		if (computed) {
			key = parseAssign();
			expectP("]");
		} else {
			key = parsePropertyName();
		}

		if (isP("(")) {
			var fn = parseFunctionRest(null, isAsync, isGen);
			return mk(Property(key, mk(FunctionExpression(fn), t), computed, kind, false, true), t);
		}
		if (eatP(":")) {
			return mk(Property(key, parseAssign(), computed, "init", false, false), t);
		}

		// Shorthand: { a } or, inside a pattern-like context, { a = 1 }
		var name = keyName(key);
		if (name == null || computed)
			fail("Invalid shorthand property", t);
		var value:Node = mk(Identifier(name), t);
		if (eatP("="))
			value = mk(AssignmentPattern(value, parseAssign()), t);
		return mk(Property(key, value, false, "init", true, false), t);
	}

	/** Property names: identifiers, keywords, strings, numbers, private names. */
	function parsePropertyName():Node {
		var t = next();
		return switch t.type {
			case TIdent, TKeyword: mk(Identifier(t.value), t);
			case TPrivate: mk(PrivateIdentifier(t.value), t);
			case TString: mk(StringLiteral(t.value), t);
			case TNumber: mk(NumberLiteral(t.numValue), t);
			case TBigInt: mk(BigIntLiteral(t.value), t);
			default: fail("Invalid property name", t);
		};
	}

	/**
	 * Parses a template literal starting at a head chunk. Substitutions are parsed as
	 * expressions; the lexer emits the continuation chunks after each closing brace.
	 */
	function parseTemplate():Node {
		var first = next();
		var cooked:Array<String> = [first.value];
		var raws:Array<String> = [first.raw];
		var exprs:Array<Node> = [];
		var tok = first;
		while (!tok.tail) {
			exprs.push(parseExpression());
			tok = next();
			if (tok.type != TTemplate)
				fail("Expected template continuation", tok);
			cooked.push(tok.value);
			raws.push(tok.raw);
		}
		return mk(TemplateLiteral(cooked, raws, exprs), first);
	}
}

class ParseError extends haxe.Exception {
	public final line:Int;
	public final col:Int;

	public function new(msg:String, line:Int, col:Int) {
		super('$msg (line $line, column $col)');
		this.line = line;
		this.col = col;
	}
}
