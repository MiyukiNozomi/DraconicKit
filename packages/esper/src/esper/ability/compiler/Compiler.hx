package esper.ability.compiler;

import esper.ability.bytecode.BytecodeWriter;
import esper.ability.bytecode.Opcodes;
import esper.ability.frontend.Ast;
import esper.ability.frontend.AstIterator;
import esper.ability.frontend.Parser;
import haxe.Exception;
import haxe.ds.StringMap;
import haxe.io.Error;
import shinku.Console.Logger;

typedef Scope = {
	depth:Int,
	isFunction:Bool,
}

enum VariableKind {
	VAR;
	LET;
	CONST;
	PARAMETER;
	FUNCTION;
}

typedef VariableSlot = {
	kind:VariableKind,
	slot:Int,
	scopeDepth:Int,
	isTopLevel:Bool,
}

class CompilerContext {
	public var parent:Null<CompilerContext>;

	public var writer:BytecodeWriter;
	public var varSlots:StringMap<Array<VariableSlot>>;

	public var funcData:Null<FunctionData>;

	public var varCount(default, null) = 0;

	public var scopes:Array<Scope>;

	var compiler:Compiler;

	public var isFunctionScope(get, never):Bool;
	public var isTopLevel(get, never):Bool;
	public var scopeDepth(get, never):Int;

	public function new(compiler:Compiler, parent:Null<CompilerContext>, ?funcData:FunctionData) {
		this.parent = parent;
		this.writer = new BytecodeWriter();
		this.varSlots = new StringMap();
		this.funcData = funcData;
		this.scopes = [];
		this.compiler = compiler;
	}

	function get_isFunctionScope()
		return scopes.length > 0 && scopes[scopes.length - 1].isFunction;

	function get_scopeDepth()
		return scopes.length;

	function get_isTopLevel() {
		return this.isFunctionScope && this.parent == null;
	}

	public function openScope(isFunction:Bool = false) {
		scopes.push({depth: scopes.length, isFunction: isFunction});
	}

	public function closeScope() {
		this.scopes.pop();

		final names = [for (k in this.varSlots.keys()) k];
		for (name in names)
			this.varSlots.set(name, this.varSlots.get(name).filter(v -> v.kind == VAR || v.scopeDepth <= scopeDepth));
	}

	public function getVariable(name:String, depth:Int = 0):Null<{
		slot:VariableSlot,
		envDepth:Int,
	}> {
		final list = this.varSlots.get(name);
		if (list == null || list.length == 0) {
			if (this.parent == null)
				return null;
			return this.parent.getVariable(name, depth + 1);
		}

		var best = list[0];
		for (v in list)
			if (v.scopeDepth > best.scopeDepth)
				best = v;
		return {
			slot: best,
			envDepth: depth
		};
	}

	public function createVariable(nd:Node, name:String, variableData:VariableSlot) {
		var existing = this.varSlots.get(name) ?? new Array();

		final createAndUpdate = () -> {
			variableData.slot = this.varCount++;
			existing.push(variableData);
			this.varSlots.set(name, existing);
			return variableData.slot;
		};

		// isn't this deviating a bit?
		if (name == "undefined" && variableData.isTopLevel)
			error({nd: nd}, "Cannot redeclare `undefined` in the top level scope.");

		switch (variableData.kind) {
			case VAR:
				{
					for (ex in existing) {
						if ((ex.kind == LET || ex.kind == CONST || ex.kind == FUNCTION)) {
							if (ex.scopeDepth <= this.scopeDepth) {
								error({nd: nd}, 'Identifier \'$name\' has already been declared.');
							}
						}
					}

					for (ex in existing) {
						// nothing changes, we just rebind if it exists.
						if (ex.kind == VAR || ex.kind == PARAMETER) {
							return ex.slot;
						}
					}
					return createAndUpdate();
				}
			case LET, CONST:
				{
					for (ex in existing) {
						if (ex.scopeDepth == variableData.scopeDepth) {
							error({nd: nd}, 'Cannot redeclare ${ex.kind == CONST ? "constant" : "variable"} \'' + name + "'");
						}
					}
					return createAndUpdate();
				}
			case FUNCTION:
				if (compiler.strictMode) {
					for (ex in existing) {
						if (ex.scopeDepth == variableData.scopeDepth) {
							error({nd: nd}, 'Cannot redeclare as function \'' + name + "'");
						}
					}
					return createAndUpdate();
				} else {
					for (ex in existing) {
						if (ex.scopeDepth == variableData.scopeDepth) {
							return ex.slot;
						}
					}
					return createAndUpdate();
				}
			case PARAMETER:
				return createAndUpdate();
		}
	}
}

class Compiler {
	var __current:Null<CompilerContext>;
	var current(get, never):CompilerContext;

	public var filename:String;
	public var rootNode:Null<Node>;
	public var strictMode:Bool = false;

	public function new(filename:String) {
		this.filename = filename;
	}

	public function compile(contents:String):EsperFunction {
		var rootNode:Node;
		try {
			rootNode = Parser.parse(contents, false); // no ESM support yet.
		} catch (p:ParseError) {
			throw new CompilerError({line: p.line, col: p.col}, p.message, "SyntaxError");
		}
		this.rootNode = rootNode;

		// access if we're in strict mode or not
		switch (rootNode.kind) {
			case Program(arr):
				if (arr.length > 0)
					this.strictMode = switch (arr[0].kind) {
						case ExpressionStatement(r): switch (r.kind) {
								case StringLiteral("use strict"): true;
								default: false;
							};
						default: false;
					}
			default:
		}

		newContext();

		this.current.openScope(true);
		this.visitNode(rootNode);
		this.current.closeScope();

		return closeFunction(null);
	}

	function visitNode(node:Node) {
		switch (node.kind) {
			case BlockStatement(body):
				this.current.openScope();
				handleScope(body);
				this.current.closeScope();
			case EmptyStatement:
			case DebuggerStatement:
				Logger.warn("Your script has a debugger statement at", node.line, "column",
					node.col + ", esper does not have a built-in debugger, it will be ignored.");
			case Program(body):
				handleScope(body);
			case VariableDeclaration(kind, declarations):
				for (dec in declarations) {
					handleDeclaration(kind, dec);
				}
			case FunctionExpression(fn):
				final jsf = compileFunc(fn);
				final index = this.current.writer.addConstant(FunctionTemplate(jsf));
				this.current.writer.write(node.line, Opcodes.MakeClosure, index);
			case FunctionDeclaration(_): // no-op.
			case Identifier(_):
				writeAquisition(node);
			default:
				this.visitExpr(node);
		}
	}

	function visitExpr(node:Node) {
		switch (node.kind) {
			case ExpressionStatement(expr):
				this.visitExpr(expr);
				current.writer.write(node.line, Opcodes.Pop);
			case Identifier(_):
				writeAquisition(node);
			case NumberLiteral(v):
				current.writer.write(node.line, Opcodes.Push, current.writer.addConstant(JSValue(Number(v))));
			case BigIntLiteral(v):
				current.writer.write(node.line, Opcodes.Push, current.writer.addConstant(JSValue(BigInt(v))));
			case StringLiteral(v):
				current.writer.write(node.line, Opcodes.Push, current.writer.addConstant(JSValue(String(v))));
			case BooleanLiteral(v):
				current.writer.write(node.line, v ? Opcodes.PushTrue : Opcodes.PushFalse);
			case NullLiteral:
				current.writer.write(node.line, Opcodes.PushNull);
			case BinaryExpression(operator_, left, right):
				this.handleBinary(node, operator_, left, right);
			default:
				error({nd: node}, "This node has not been implemented in the compiler:", node.kind.getName());
		}
	}

	function handleBinary(nd:Node, operator_:String, left:Node, right:Node) {
		this.visitExpr(left);
		this.visitExpr(right);

		current.writer.write(nd.line, switch (operator_) {
			case "+": Opcodes.Add;
			case "-": Opcodes.Sub;
			case "/": Opcodes.Div;
			case "*": Opcodes.Mul;
			case "%": Opcodes.Mod;

			case "==": Opcodes.CheckEqual;
			case "!=": Opcodes.CheckNotEqual;

			case "===": Opcodes.CheckEqualStrictType;
			case "!==": Opcodes.CheckNotEqualStrictType;

			case ">": Opcodes.GreaterThan;
			case ">=": Opcodes.GreaterOrEqual;
			case "<": Opcodes.LessThan;
			case "<=": Opcodes.LessOrEqual;
			default:
				error({nd: nd}, "Operator not implemented in handleBinary!");
				Opcodes.Nop;
		});
	}

	function handleScope(body:Array<Node>) {
		for (nd in body)
			handleHoist(nd);
		for (nd in body)
			instantiateFunction(nd);
		// now we can evaluate as normal
		for (nd in body)
			visitNode(nd);
	}

	function handleDeclaration(kind:String, declarator:Node) {
		// Kind here will always be either: var, let or const.
		switch (declarator.kind) {
			case VariableDeclarator(id, initializer):
				writeAssignment(kind, id, initializer, true);
			default:
				error({nd: declarator}, "Unexpected node type! wanted VariableDeclarator.");
		}
	}

	function writeAssignment(kind:String, id:Node, value:Null<Node>, isDeclaration = false) {
		var stringId = identifierOrThrow(id);

		var variableInfo = this.current.getVariable(stringId);

		if (value == null) {
			if (isDeclaration && kind == "var")
				return; // dont generate anything for var a; so we dont overwrite anything.
			this.current.writer.write(id.line, Opcodes.PushUndefined);
		} else
			this.visitNode(value);

		if (variableInfo == null || isSlotGlobal(variableInfo.slot)) {
			this.current.writer.writeStringOp(id.line, Opcodes.SetGlobal, stringId);
			return;
		}

		if (variableInfo.slot.kind == CONST && isDeclaration && value == null)
			error({nd: id}, "Missing initializer in const declaration");

		if (isDeclaration)
			this.current.writer.write(id.line, switch (variableInfo.slot.kind) {
				case VAR, PARAMETER: Opcodes.DefineVar;
				case LET, FUNCTION: Opcodes.DefineLocal;
				case CONST: Opcodes.DefineConstant;
			}, variableInfo.slot.slot);
		else
			this.current.writer.write(id.line, switch (variableInfo.slot.kind) {
				case VAR, PARAMETER: Opcodes.SetVar;
				case LET, FUNCTION: Opcodes.SetLocal;
				case CONST: Opcodes.Nop;
			}, variableInfo.slot.slot, variableInfo.envDepth);
	}

	function writeAquisition(id:Node) {
		var stringId = identifierOrThrow(id);

		var variableInfo = this.current.getVariable(stringId);

		if (stringId == "undefined" && variableInfo == null) {
			this.current.writer.write(id.line, Opcodes.PushUndefined);
			return;
		}

		if (variableInfo == null || isSlotGlobal(variableInfo.slot)) {
			this.current.writer.writeStringOp(id.line, Opcodes.GetGlobal, stringId);
			return;
		}

		this.current.writer.write(id.line, switch (variableInfo.slot.kind) {
			case VAR, PARAMETER: Opcodes.GetVar;
			case LET, FUNCTION: Opcodes.GetLocal;
			case CONST: Opcodes.GetConstant;
		}, variableInfo.slot.slot, variableInfo.envDepth);
	}

	function handleHoist(nd:Node, depth = 0) {
		switch (nd.kind) {
			case VariableDeclaration(kind, declarations):
				if (depth > 0 && kind != "var")
					return;
				for (dec in declarations) {
					switch (dec.kind) {
						case VariableDeclarator(id, _):
							this.current.createVariable(nd, identifierOrThrow(id), {
								kind: switch (kind) {
									case "var": VAR;
									case "let": LET;
									case "const": CONST;
									default:
										error({nd: nd}, "Not implemented: " + kind);
										VAR;
								},
								slot: 0,
								isTopLevel: current.isTopLevel,
								scopeDepth: current.scopeDepth,
							});
						default:
							error({nd: dec}, "Unexpected node type! wanted VariableDeclarator.");
					}
				}
			// no action for these
			case FunctionExpression(_):
			case FunctionDeclaration(fn):
				if (depth > 0)
					return;
				if (fn.name == null)
					throw Error.Custom("Fatal: FunctionDeclaration name is NULL! " + Std.string(nd));
				// stupid nullsafety..
				this.current.createVariable(nd, fn.name ?? "", {
					kind: this.current.isFunctionScope ? VAR : FUNCTION,
					slot: 0,
					scopeDepth: current.scopeDepth,
					isTopLevel: current.isTopLevel,
				});
			default:
				for (n in Ast.children(nd)) {
					handleHoist(n, depth + 1);
				}
		}
	}

	function instantiateFunction(nd:Node) {
		switch (nd.kind) {
			case FunctionDeclaration(fn):
				final jsf = compileFunc(fn);
				final idx = this.current.writer.addConstant(FunctionTemplate(jsf));
				this.current.writer.write(nd.line, Opcodes.MakeClosure, idx);

				if (fn.name == null)
					throw Error.Custom("Fatal: FunctionDeclaration name is NULL! " + Std.string(nd));

				var variableInfo = this.current.getVariable(fn.name ?? "");
				if (variableInfo == null)
					throw Error.Custom("Function not registered! " + Std.string(nd));

				if (isSlotGlobal(variableInfo.slot)) {
					this.current.writer.writeStringOp(nd.line, Opcodes.SetGlobal, fn.name ?? "");
				} else if (this.current.isFunctionScope) {
					this.current.writer.write(nd.line, Opcodes.SetVar, variableInfo.slot.slot, 0);
				} else {
					this.current.writer.write(nd.line, Opcodes.SetLocal, variableInfo.slot.slot, 0);
				}
			default:
		}
	}

	function compileFunc(fn:FunctionData) {
		newContext(fn);

		this.current.openScope(true);

		for (param in fn.params) {
			switch (param.kind) {
				case Identifier(id):
					this.current.createVariable(param, id, {
						kind: PARAMETER,
						scopeDepth: this.current.scopeDepth,
						slot: 0,
						isTopLevel: current.isTopLevel,
					});
				default:
					error({nd: param}, "Node type in function parameter not implemented: ", param);
			}
		}
		switch (fn.body.kind) {
			case BlockStatement(body):
				handleScope(body);
			default:
				error({nd: fn.body}, "Function body must be a block statement");
		}

		this.current.closeScope();
		return this.closeFunction(fn);
	}

	function closeFunction(fn:Null<FunctionData>) {
		if (!this.current.writer.returnWritten)
			this.current.writer.write(-1, Opcodes.Return);
		var jsf = this.current.writer.toFunction(this.current.varCount, this.filename, (fn != null ? fn.name : null) ?? "<script>");
		this.__current = this.current.parent;
		return jsf;
	}

	function newContext(?fn:FunctionData) {
		this.__current = new CompilerContext(this, this.__current, fn);
	}

	function identifierOrThrow(id:Node) {
		return switch (id.kind) {
			case Identifier(r): return r;
			default:
				error({nd: id}, "Wanted Identifier but got", id.kind.getName(), "instead!");
				return "";
		}
	}

	function get_current():CompilerContext {
		if (this.__current == null)
			throw Error.Blocked;
		return this.__current;
	}
}

class CompilerError extends Exception {
	public var location:{line:Int, col:Int};
	public var errorName:String;

	public function new(location:{line:Int, col:Int}, message:String, errorName:String) {
		super(message);

		this.errorName = errorName;
		this.location = {
			line: location.line,
			col: location.col
		};
	}
}

private function isSlotGlobal(slot:VariableSlot) {
	return slot.isTopLevel && (slot.kind == VAR || slot.kind == FUNCTION);
}

private function error(info:{nd:Null<Node>, ?errorType:String}, ...msg:Dynamic) {
	throw new CompilerError({
		line: info.nd != null ? info.nd.line : -1,
		col: info.nd != null ? info.nd.col : -1
	}, msg.toArray().map(v -> Std.string(v)).join(" "),
		info.errorType ?? "SyntaxError");
}
