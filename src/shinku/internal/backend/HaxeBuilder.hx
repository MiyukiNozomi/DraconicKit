package shinku.internal.backend;

import sys.io.File;
import shinku.std.io.SystemTools;
import shinku.Console.Logger;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.Process;
import sys.thread.Lock;
import sys.thread.Thread;

class HaxeBuilder {
	final projectDir:String;
	final hxml:String;
	final genDir:String;
	final wake = new Lock();
	final onBuilt:(jar:String) -> Void;
	final onFailed:(errors:String) -> Void;
	var generation = 0;

	public function new(projectDir:String, onBuilt, onFailed) {
		this.projectDir = projectDir;
		this.onBuilt = onBuilt;
		this.onFailed = onFailed;
		hxml = Path.join([projectDir, ".shinku", "build.hxml"]);
		genDir = Path.join([projectDir, ".shinku", "gen"]);
		FileSystem.createDirectory(genDir);
		Thread.create(loop);
	}

	public function request()
		wake.release();

	function loop() {
		while (true) {
			wake.wait();
			Sys.sleep(0.15);
			while (wake.wait(0.0)) {}
			build();
		}
	}

	function build() {
		this.setupHiddenDirectoryForHaxe();

		final jar = Path.join([genDir, 'user-${generation + 1}.jar']);
		final t0 = Sys.time();
		final p = new Process("haxe", ["--cwd", projectDir, hxml, "--jvm", jar]);

		final err = p.stderr.readAll().toString();
		final out = p.stdout.readAll().toString();
		final code = p.exitCode();
		p.close();

		if (code != 0) {
			onFailed(err + out); // keep the previous generation serving
			return;
		}
		generation++;
		Logger.debug('haxe build ok in ${Math.round((Sys.time() - t0) * 1000)}ms');
		onBuilt(jar);
	}

	private function setupHiddenDirectoryForHaxe() {
		final shinkuDir = Path.join([Configuration.WorkingDirectory, ".shinku"]);
		FileSystem.createDirectory(shinkuDir);

		final hacksDir = Path.join([shinkuDir, "hacks"]);
		FileSystem.createDirectory(hacksDir);

		final hxmlFilePath = Path.join([shinkuDir, "build.hxml"]);
		if (!FileSystem.exists(hxmlFilePath)) {
			File.saveContent(hxmlFilePath, '
# just sanity check
-dce std
--class-path src
--class-path .shinku/hacks
--class-path ${FileSystem.absolutePath(Path.join([SystemTools.thisHomeDir(), "src/"]))}
--main StubsMain
');
		}

		final stubMainPath = Path.join([hacksDir, "StubsMain.hx"]);
		if (!FileSystem.exists(stubMainPath)) {
			final stubsMainCode = '
@:build(IncludeAll.run("../../src"))
class StubsMain {
	static function main() {
		trace("DO NOT RUN THIS! - this is not your server! read the docs!"); 
	}
}		
';
			File.saveContent(stubMainPath, stubsMainCode);
		}
	}
}
