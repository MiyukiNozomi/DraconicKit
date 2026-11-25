package esper.ability.vm;

import esper.ability.vm.EsperVM.EsperVMFault;

class EsperVMStack<T> {
	static final STACK_MAX_SIZE = 200;

	var container:Array<T>;
	var pointer = 0;

	public var isEmpty(get, never):Bool;

	public function new() {
		this.container = new Array();
		this.container.resize(STACK_MAX_SIZE);
	}

	function get_isEmpty()
		return pointer == 0;

	public function debugPrint() {
		Sys.println("Stack: " + this.container.slice(0, pointer).map(v -> Std.string(v)).join(" "));
	}

	public function iterator() {
		final cpy = this.container.map(v -> v);
		cpy.reverse();
		return cpy.iterator();
	}

	public function push(v:T) {
		if (pointer >= STACK_MAX_SIZE)
			throw new EsperVMFault("Stack overflow");
		this.container[pointer++] = v;
	}

	public function pop() {
		if (pointer <= 0)
			throw new EsperVMFault("Stack underflow");
		return this.container[--pointer];
	}

	public function peek(dist:Int) {
		if (pointer - dist <= 0)
			throw new EsperVMFault("Stack underflow");
		return this.container[--pointer];
	}
}
