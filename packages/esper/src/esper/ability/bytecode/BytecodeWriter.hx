package esper.ability.bytecode;

import esper.ability.bytecode.Opcodes;
import haxe.io.BytesBuffer;
import haxe.io.Error;

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
		var bytes = haxe.io.Bytes.ofString(str, UTF8);

		buffer.addByte(opcode);
		buffer.addInt32(bytes.length);
		buffer.add(bytes);
		this.ensureLine(line);
	}

	public function write(line:Int, ...opcodes:Int) {
		if (opcodes.length == 0)
			throw Error.Custom("opcodes list cannot be empty!");

		buffer.addByte(opcodes[0]);

		for (i in 1...opcodes.length)
			buffer.addInt32(opcodes[i]);

		this.ensureLine(line);
	}

	public function toFunction(varCount, filename, funcName) {
		return new EsperFunction(filename, funcName, varCount, buffer.getBytes(), constants, lines);
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
