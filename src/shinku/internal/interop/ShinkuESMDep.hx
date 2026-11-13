package shinku.internal.interop;

import haxe.Json;
import shinku.std.io.SystemTools;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;

class ShinkuESMDep {
	public static function setupModule(directory = Configuration.WorkingDirectory, force = false) {
		final p = Path.join([directory, ".shinku", "esm"]);
		if (force || !FileSystem.exists(p)) {
			FileSystem.createDirectory(p);
			File.saveContent(Path.join([p, "index.js"]), hx2ESM(Path.join([SystemTools.thisHomeDir(), "bin/shinku.js"])));
			File.saveContent(Path.join([p, "package.json"]), Json.stringify({
				"name": "shinku",
				"description": "DraconicKit's internal package.",
				"version": Configuration.Version,
				"type": "module",
				"exports": {
					".": "./index.js"
				}
			}));
		}
	}

	static function hx2ESM(path:String) {
		return '
const exports = {};
${File.getContent(path)}
 
export const Shinku = exports.Shinku;
export default Shinku;
';
	}
}
