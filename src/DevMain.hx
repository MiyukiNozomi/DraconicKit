import shinku.internal.commands.HelpCommand;
import shinku.Console.AnsiPrinter;
import shinku.Console.Logger;
import shinku.internal.commands.InitCommand;
import shinku.internal.devserver.DevServer;

using StringTools;

#if draconicbuilder
// Dev Main as in "Development Mode Main"
// Dev Server in shinku.internal.devserver.DevServer
class DevMain {
	static function main() {
		#if draconicdev
		AnsiPrinter.print("§1;91mWARNING: You are running a development build. recompile with build-release.hxml on DraconicKit's project folder and reinstall if this was unintentional.\n");
		Logger.debug("Test");
		Logger.info("Test");
		Logger.warn("Test");
		Logger.error("Test");
		#end

		final args = Sys.args();

		AnsiPrinter.print("§1;91mWARNING: This project is in an extreme early stage. It may have many edge cases.\n");
		if (args.length == 0 || args[0] == "help") {
			HelpCommand.print();
		} else if (args[0] == "init") {
			InitCommand.projectInit(args);
		} else if (args[0] == "dev") {
			DevServer.runDevServer();
		} else if (args[0] == "build") {
			AnsiPrinter.print('§1;93mSorry this is not implemented! production builder is coming soon!\n');
		} else {
			AnsiPrinter.print('§1;91mCommand not recognized: §1;37m${args[0]}\n');
		}
	}
}
#end
