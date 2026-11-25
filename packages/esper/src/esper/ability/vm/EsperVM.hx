package esper.ability.vm;

import esper.ability.bytecode.Opcodes;
import esper.ability.compiler.Disassembler;
import esper.ability.vm.Value.JSEnvironment;
import esper.ability.bytecode.Opcodes.EsperFunction;
import esper.ability.vm.Value.JSValue;
import esper.ability.vm.Value.JSFunction;
import haxe.Exception;

typedef Global = {
	isImmutable:Bool,
	value:JSValue,
}

typedef CallFrame = {
	ip:Int,
	func:JSFunction,
	bytecode:EsperFunction,
	closure:JSEnvironment
}

class EsperVM {
	var stack:EsperVMStack<JSValue>;
	var callStack:EsperVMStack<CallFrame>;

	var globals:Map<String, Global>;

	@:nullSafety(Off)
	var frame:CallFrame;

	public function new() {
		this.stack = new EsperVMStack();
		this.callStack = new EsperVMStack();

		this.globals = [
			"undefined" => {
				isImmutable: true,
				value: Undefined
			}
		];
	}

	function makeFrame(func:JSFunction):CallFrame {
		return switch (func.impl) {
			case Bytecode(v, closure):
				({
					ip: 0,
					func: func,
					bytecode: v,
					closure: closure
				});
			default: throw new EsperVMFault("Cannot make a frame for a native function.");
		};
	}

	public function interpret(raw:EsperFunction) {
		this.call(new JSFunction(Bytecode(raw, new JSEnvironment())));
	}

	public function call(func:JSFunction) {
		this.callStack.push(makeFrame(func));
		this.start();
	}

	function start() {
		try {
			while (!this.callStack.isEmpty) {
				this.process();
			}
		} catch (err:EsperVMFault) {
			throw this.insertJSStack(err);
		}
	}

	function process() {
		this.frame = this.callStack.pop();

		while (true) {
			this.stack.debugPrint();
			Disassembler.disassembleInstruction(this.frame.bytecode, this.frame.ip);

			final op:Opcodes = this.nextByte();

			switch (op) {
				case EndOfFile:
					return; // EOF must leave?
				case Nop:

				case Push:
					{
						final v = this.frame.bytecode.constants[nextInt()];
						this.stack.push(switch (v) {
							case JSValue(jsv): jsv;
							default:
								throw new EsperVMFault("Cannot use 'Push' for this value: " + Std.string(v));
						});
					}
				case PushUndefined:
					this.stack.push(Undefined);
				case PushNull:
					this.stack.push(Null);
				case PushTrue:
					this.stack.push(Boolean(true));
				case PushFalse:
					this.stack.push(Boolean(false));
				case Pop:
					this.stack.pop();

				// TODO: MakeClosure

				case Return:
					return;
				default:
					throw new EsperVMFault("Opcode not implemented: " + AbstractEnumTools.toName(op));
			}
		}
	}

	function nextByte() {
		return this.frame.bytecode.bytes.get(this.frame.ip++);
	}

	function nextInt() {
		final r = this.frame.ip;
		this.frame.ip += 4;
		return this.frame.bytecode.bytes.getInt32(r);
	}

	function nextString() {
		final l = nextInt();
		final s = this.frame.bytecode.bytes.getString(this.frame.ip, l);
		this.frame.ip += l;
		return s;
	};

	function insertJSStack(err:Exception) {
		for (frame in this.callStack.iterator()) {
			// TODO
		}
		return err;
	}
}

class EsperVMFault extends Exception {}
class JSException extends EsperVMFault {}
