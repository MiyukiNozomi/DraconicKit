package shinku.internal.commands;

import haxe.Json;
import haxe.io.Path;
import shinku.Console.AnsiPrinter;
import shinku.internal.StdinPrompt;
import shinku.std.io.SystemTools;
import sys.FileSystem;
import sys.io.File;

using StringTools;

class InitCommand {
	// TODO: delete directory on failure?
	public static function projectInit(args:Array<String>) {
		final username = SystemTools.getSystemUsername() ?? "Unnamed Dragon";

		AnsiPrinter.print('§0;36m Hello there §1;96m$username! §0;36mWelcome to §1;91mDraconicKit§0;36m, let me walk you through the setup. \n\n');

		var directory = "./";
		var projectName = "";

		if (args.length > 1 && !args[1].startsWith("-")) {
			directory = args[1];
			projectName = Path.withoutDirectory(directory);
			if (projectName == "" || projectName == "." || projectName == "..") {
				projectName = "";
			}
		}

		var exists = FileSystem.exists(directory);

		if (exists) {
			if (!FileSystem.isDirectory(directory)) {
				AnsiPrinter.print('\n§1;91m\u25C6 Cancelled: $directory is a file. \n\n');
				return;
			}

			if (!StdinPrompt.confirm('Directory $directory already exists ${FileSystem.readDirectory(directory).length > 0 ? "(and has files)" : "(but it is empty)"}, are you sure you want to continue?')) {
				return;
			}
		}

		var initName = projectName;
		do {
			projectName = StdinPrompt.ask("Input your project name", initName.length > 0 ? initName : null);
			if (~/^(@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$/.match(projectName)) {
				break;
			} else {
				AnsiPrinter.print("   §0;93mSorry, give it another name! if I were to write that into your package.json, your package manager would be pretty mad.\n");
			}
		} while (true);

		var packageManager;
		do {
			packageManager = StdinPrompt.choose("Choose a package manager (this is for frontend dependencies, not backend):", ["npm", "yarn", "pnpm"]);
			if (packageManager == "pnpm") {
				AnsiPrinter.print("\n\n§0;33mJust a small note about 'pnpm', during testing it appears it's node_modules layout is different, and DraconicKit's ESM resolver kinda gives up because of this. the option is still available though.\n\n\n");
				if (StdinPrompt.confirm("Would you like to continue?"))
					break;
			} else
				break;
		} while (true);

		var license = StdinPrompt.ask("Which license would you like?", "proprietary");

		if (StdinPrompt.confirm("Is information below correct? " + Json.stringify({
			"project-name": projectName,
			"package-manager": packageManager,
			"on-directory": directory,
			license: license
		}, "\t"))) {
			AnsiPrinter.print(" §0;93m*=- §0;90mCopying template project...\n");
			SystemTools.recursiveCopy(Path.join([SystemTools.thisHomeDir(), "template-project"]), directory);

			final ourSvelteVersion = Json.parse(File.getContent(Path.join([SystemTools.thisHomeDir(), "package.json"]))).dependencies.svelte;
			AnsiPrinter.print(" §0;93m*=- §0;90mWriting package file...\n");
			File.saveContent(Path.join([directory, "package.json"]), Json.stringify({
				name: projectName,
				version: "1.0.0",
				type: "module",
				author: username,
				contributors: [username, "The DraconicKit People"],
				dependencies: {
					// ideally we want to use the same svelte version, reason being that the svelte compiler invoked by DraconicKit is the builder's own install and not the project's.
					// So to avoid incompatibilities of built svelte internal dependencies between project and builder we force it to use the same svelte version.
					"svelte": ourSvelteVersion
				},
				license: license
			}, "\t"));
			AnsiPrinter.print(' §0;93m*=- §0;90mInstalling dependencies with $packageManager...\n');

			var cmd = [packageManager];
			if (packageManager != "yarn")
				cmd.push("install");
			var exitCode = SystemTools.runShellCommandAt(cmd, FileSystem.absolutePath(directory));
			if (exitCode != 0) {
				AnsiPrinter.print('\n§1;91m\u25C6 Project setup failed! $packageManager has exited with exit code $exitCode!

;94mThis is not the end of the world however, you can try to install them yourself by running ${cmd.join(" ")}. 
');
				return;
			}

			AnsiPrinter.print('
§1;94mInitialization complete!
	
§0;90mRun §1;36mdraconickit dev§0;90m to launch your project. And use $packageManager to install your frontend dependencies, have fun!.
§0;91m§3mMay the rage of the dragon protect you from JavaScript. And thou server shall not suffer with it\'s evil doings.
');
		} else {
			AnsiPrinter.print("\n§1;91m\u25C6 Cancelled!\n\n");
		}
	}
}
