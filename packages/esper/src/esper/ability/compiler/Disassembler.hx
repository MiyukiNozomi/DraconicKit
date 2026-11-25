package esper.ability.compiler;

import esper.ability.bytecode.Opcodes.EsperFunction;
import esper.ability.bytecode.Opcodes;

using StringTools;

class Disassembler {
	public static function disassemble(func:EsperFunction) {
		for (con in func.constants) {
			switch (con) {
				case FunctionTemplate(v):
					disassemble(v);
				default:
			}
		}

		Sys.println(func.filename + ":" + func.funcName + ":\n data (" + func.constants.length + ")");

		for (i => con in func.constants) {
			Sys.print(" " + i + " ");
			switch (con) {
				case FunctionTemplate(v):
					Sys.println(v.filename + ":" + v.funcName);
				case JSValue(v):
					Sys.println(Std.string(v));
			}
		}

		Sys.println(" text (" + func.bytes.length + " - " + func.lines.length + ")");

		var i = 0;

		while (i < func.bytes.length)
			i = disassembleInstruction(func, i);

		Sys.println('');
	}

	public static function disassembleInstruction(func:EsperFunction, i:Int) {
		final b:Opcodes = func.bytes.get(i++);

		final w = (d:Array<Dynamic>) -> {
			Sys.print(d.map(v -> Std.string(v)).join(' '));
		};

		final nextInt = () -> {
			final r = i;
			i += 4;
			return func.bytes.getInt32(r);
		}
		final nextString = () -> {
			final l = nextInt();
			final s = func.bytes.getString(i, l);
			i += l;
			return s;
		};

		w([
			"  ",
			Std.string(func.getLineAt(i)).lpad('0', 4),
			Std.string(i - 1).lpad('0', 4),
			AbstractEnumTools.toName(b),
			""
		]);

		switch (b) {
			case Push, MakeClosure:
				final ii = nextInt();
				w([ii, func.constants[ii]]);

			case Jump, JumpIfFalse:
				{
					final v = nextInt();
					w([v, "(" + i + " -> " + v + ")"]);
				}

			case DefineVar, DefineLocal, DefineConstant:
				w([nextInt()]);

			case SetVar, GetVar, SetLocal, GetLocal, GetConstant, SetConstant:
				w([nextInt(), nextInt()]);

			case DefineGlobal, SetGlobal, GetGlobal:
				w(['"' + nextString() + '"']);
			default:
		}
		Sys.println('');

		return i;
	}
}
