package shinku.internal.commands;

import shinku.Console.Logger;
import shinku.Console.AnsiPrinter;

class HelpCommand {
	static final HELP_LINES = [
		{
			name: "help",
			description: 'Basically this command.'
		},
		{
			name: "init",
			description: "Initializes a DraconicKit project.\n" + "Use `init [dirname]` to specify a directory (optional).\n" +
			"If omitted, the project name will be prompted."
		},
		{
			name: "dev",
			description: "Runs your project in development mode,\n with hot swapping enabled."
		},
		{
			name: "build",
			description: "Builds your project in development mode,\n currently it will only build for the JVM target (still need to polish some stuff.)"
		}
	];

	// heads up that this isnt exactly based on how the terminal handles unicodes
	// TODO. make it unicode aware so we will still have text aligned no matter the terminal config
	static function printHelp(sidebar:Array<String>) {
		var totalLines = new Array<String>();

		var v = new Array<String>();
		v.resize(AnsiPrinter.removeColors(sidebar[0]).length);
		var emptyLine = v.map(v -> ' ').join('');

		var consumed = 0;
		var consume = () -> {
			if (consumed >= sidebar.length || AnsiPrinter.removeColors(sidebar[consumed]).length == 0) {
				consumed++;
				return emptyLine;
			}
			return sidebar[consumed++];
		}
		totalLines.push(consume());
		totalLines.push(consume() + " §0;93m -=* §0;36mhttps://github.com/MiyukiNozomi/DraconicKit §0;93m*=-");
		totalLines.push(consume());
		for (line in HELP_LINES) {
			totalLines.push(consume() + " §0;93m*=- §0;94m" + line.name);
			totalLines.push(consume());

			for (descriptionLine in line.description.split("\n")) {
				totalLines.push(consume() + "     §0;90m" + descriptionLine);
			}

			totalLines.push(consume());
		}

		AnsiPrinter.print(totalLines.join('\n') + "\n");
	}

	static function fullSizeHelp() {
		AnsiPrinter.print('§0;95m
§0;95m⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀ 
§0;95m⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀§0;91m ▄▄▄▄▄▄                                         ▄▄▄▄   ▄▄▄       
§0;95m⠀⠀⠀⠀⠀⠀⠘⢶⣦⠀⣼⣿⣿⣧⠀⣴⡶⠃⠀⠀⠀⠀⠀⠀§0;91m █▀██▀▀██                                       █▀ ██  ██      █▄ 
§0;95m⠀⠀⠀⠀⠀⠀⠀⣀⣻⣿⣿⣿⣿⣿⣿⣟⣀⠀⠀⠀⠀⠀⠀⠀§0;91m   ██   ██ ▄                      ▄     ▀▀         ██ ██    ▀▀▄██▄
§0;95m⠀⠀⠀⣤⣴⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣦⣤⠀⠀⠀§0;91m   ██   ██ ████▄▄▀▀█▄ ▄███▀ ▄███▄ ████▄ ██ ▄███▀   █████    ██ ██ 
§0;95m⠀⠀⠀⠀⠉⠉⠛⠻⢿⣿⣿⣿⣿⣿⣿⡿⠟⠛⠉⠉⠀⠀⠀⠀§0;91m ▄ ██   ██ ██   ▄█▀██ ██    ██ ██ ██ ██ ██ ██      ██ ██▄   ██ ██ 
§0;95m⠀⠀⠀⠀⠀⠀⠀⣰⡿⠟⣿⣿⣿⣿⠻⢿⣆⠀⠀⠀⠀⠀⠀⠀§0;91m ▀██▀███▀ ▄█▀  ▄▀█▄██▄▀███▄▄▀███▀▄██ ▀█▄██▄▀███▄ ▀██▀  ▀██▄▄██▄██ \n');
		printHelp('§0;95m⠀⠀⠀⠀⠀⠀⠘⠋⠀⠀⢻⣿⣿⡟⠀⠀⠙⠃⠀⠀⠀⠀⠀⠀
§0;95m⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
§0;95m⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
§0;95m⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
§0;95m⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
§0;95m
'.split('\n'));
	}

	static function smallSizeHelp() {
		AnsiPrinter.print('§0;91m === §1;91mDRACONIC §0;95m\u2726§1;91m KIT §0;91m=== ');
		printHelp([' ']);
	}

	public static function print() {
		if (Logger.getTerminalSize().cols < 96)
			smallSizeHelp();
		else
			fullSizeHelp();
	}
}
