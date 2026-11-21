package esper.ability.bytecode;

import esper.ability.vm.Value.JSValue;
import esper.ability.vm.Value.JSValue;
import haxe.io.Bytes;

enum abstract Opcodes(Int) from Int to Int {
	var EndOfFile = 0x00;

	var Push;
	var PushUndefined;
	var PushNull;
	var PushTrue;
	var PushFalse;

	var MakeClosure;

	var Add;
	var Sub;
	var Div;
	var Mul;
	var Mod;

	var Jump;
	var JumpIfFalse;

	var DefineVar;
	var SetVar;
	var GetVar;

	var DefineLocal;
	var SetLocal;
	var GetLocal;

	var DefineConstant;
	var SetConstant;
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

	public var requiredVarSlotCount:Int;

	public function new(requiredVarSlotCount, bytes, constants, lines) {
		this.requiredVarSlotCount = requiredVarSlotCount;
		this.bytes = bytes;
		this.constants = constants;
		this.lines = lines;
	}
}
