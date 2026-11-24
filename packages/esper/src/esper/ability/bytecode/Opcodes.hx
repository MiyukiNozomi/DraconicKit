package esper.ability.bytecode;

import esper.ability.vm.Value.JSValue;
import haxe.io.Bytes;

enum abstract Opcodes(Int) from Int to Int {
	var EndOfFile = 0x00;
	var Nop;

	var Push;
	var PushUndefined;
	var PushNull;
	var PushTrue;
	var PushFalse;
	var Pop;

	var MakeClosure;

	var Add;
	var Sub;
	var Div;
	var Mul;
	var Mod;

	var CheckEqual;
	var CheckNotEqual;

	var CheckEqualStrictType;
	var CheckNotEqualStrictType;

	var LessThan;
	var GreaterThan;
	var LessOrEqual;
	var GreaterOrEqual;

	var Jump;
	var JumpIfFalse;

	var DefineVar;
	var SetVar;
	var GetVar;

	var DefineLocal;
	var SetLocal;
	var GetLocal;

	var DefineConstant;
	var GetConstant;

	var DefineGlobal;
	var SetGlobal;
	var GetGlobal;

	var Call;
	var CallFromParent;

	var Return;
}

typedef LineNumber = {
	line:Int,
	endOffset:Int
};

enum ConstantPoolValue {
	JSValue(v:JSValue);
	FunctionTemplate(v:EsperFunction);
}

class EsperFunction {
	public var bytes:Bytes;
	public var constants:Array<ConstantPoolValue>;
	public var lines:Array<LineNumber>;

	public var filename:String;
	public var funcName:String;

	public var requiredVarSlotCount:Int;

	public function new(filename, funcName, requiredVarSlotCount, bytes, constants, lines) {
		this.filename = filename;
		this.funcName = funcName;

		this.requiredVarSlotCount = requiredVarSlotCount;
		this.bytes = bytes;
		this.constants = constants;
		this.lines = lines;
	}

	public function getLineAt(offs:Int) {
		var lastLine = -1;

		for (ln in this.lines) {
			lastLine = ln.line;
			if (ln.endOffset >= offs)
				break;
		}

		return lastLine;
	}
}
