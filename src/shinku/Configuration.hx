package shinku;

class Configuration {
	/**
		Current version of DraconicKit
	**/
	public static final Version = "0.1.0";

	#if draconicdev
	public static var ShowDebugLogs = true;
	#else
	public static var ShowDebugLogs = false;
	#end

	/**
		This option makes the server print the status line of incoming requests
	**/
	public static var ShowDevRequests = false;

	/**
		Whatever or not `Logger` functions should print a timestamp.

		@see shinku.Logger 
	**/
	public static var ShowTimestampLogs = true;

	/**
		Whatever or not `Logger` functions should be printed with colors.
		Also affects `AnsiPrinter`.

		@see shinku.Logger 
		@see shinku.AnsiPrinter
	**/
	public static var UseColorsInLogs = true;

	/**
		Makes DraconicKit delete it's data directory (e.g, `.shinku`) every time it starts so it's rebuilt from scratch.
	**/
	#if draconicdev
	public static var CleanupAlways = true;
	#else
	public static var CleanupAlways = false;
	#end

	/**
		Set's a working directory, you should not really touch this. it's also only here for legacy purposes.

		@deprecated Will eventually be removed.
	**/
	public static var WorkingDirectory:String = "";

	/**
		Defines the name of your project's static directory. 

		Files inside of it are served without a prefix, so if you have `static/suisei.png`, requesting `/suisei.png` will return that file.
	**/
	public static var StaticDirectory:String = "static/";
}
