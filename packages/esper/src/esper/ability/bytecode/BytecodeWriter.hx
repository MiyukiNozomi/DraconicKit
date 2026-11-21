package esper.ability.bytecode;

import haxe.io.Error;
import esper.ability.vm.Value;
import esper.ability.bytecode.Opcodes;
import haxe.io.BytesBuffer;

class BytecodeWriter {
	public var buffer:BytesBuffer;
	public var constants:Array<ConstantPoolValue>;
	public var lines:Array<LineNumber>;

	public var returnWritten:Bool;

	public function new() {
		this.buffer = new BytesBuffer();
		this.constants = [];
		this.lines = [];
		this.returnWritten = false;
	}

	public function addConstant(v:ConstantPoolValue) {
		// TODO: keep it from adding duplicate constants
		var id = this.constants.length;
		this.constants.push(v);
		return id;
	}

	public function writeStringOp(line:Int, opcode:Int, str:String) {
		buffer.addByte(opcode);
		buffer.addInt32(str.length);
		buffer.addString(str, UTF8);
		this.ensureLine(line);
	}

	public function write(line:Int, ...opcodes:Int) {
		if (opcodes.length == 0)
			throw Error.Custom("opcodes list cannot be empty!");

		buffer.addByte(opcodes[0]);
		for (op in opcodes)
			buffer.addInt32(op);
		this.ensureLine(line);
	}

	public function toFunction(varCount) {
		return new EsperFunction(varCount, buffer.getBytes(), constants, lines);
	}

	function ensureLine(line:Int) {
		if (lines.length == 0 || lines[lines.length - 1].line != line) {
			lines.push({
				line: line,
				endOffset: buffer.length
			});
		} else {
			lines[lines.length - 1].endOffset = buffer.length;
		}
	}
}
