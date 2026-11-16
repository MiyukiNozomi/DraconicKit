import esper.Codegen;
import esper.Parser;

class EsperTest {
	static function main() {
		var source = "
			import foo from 'foooooooo';
			const add = (a, b = 2) => a + b;
			class Counter extends Base {
				#count = 0;
				increment() { this.#count++; }
			}
			for (const [k, v] of Object.entries({ x: 1 })) console.log(`\\${k}=\\${v}`);
			const mod = await import('./mod.js');
			console.log(import.meta.url);
			export { add as sum };
			export * as utils from './utils.js';
		";

		var program = Parser.parse(source, true);

		Sys.println(Codegen.generate(program));
	}
}
