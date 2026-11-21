package esper.ability.frontend;

enum TokenType {
	TIdent; // identifiers, including contextual keywords such as let, async, of, get, set
	TKeyword; // reserved words
	TPrivate; // #name (value holds the name without '#')
	TNumber; // numeric literal (numValue holds the value)
	TBigInt; // numeric literal with 'n' suffix (value holds the digits)
	TString; // string literal (value holds the cooked string)
	TTemplate; // template chunk (value holds the cooked text, see head/tail)
	TRegExp; // regular expression literal (value = pattern, flags = flags)
	TPunct; // operators and punctuation
	TEOF;
}

class Token {
	public final type:TokenType;
	public final value:String;
	public final line:Int;
	public final col:Int;
	public final start:Int;
	public final end:Int;

	// True when a line terminator appears between the previous token and this one (used for ASI).
	public final newlineBefore:Bool;

	public var numValue:Float = 0;
	public var flags:String = "";

	// Raw source text of a template chunk.
	public var raw:String = "";

	// Template chunk begins with a backtick (it is the start of a template, not a continuation).
	public var head:Bool = false;

	// Template chunk ends with a backtick (no more substitutions follow).
	public var tail:Bool = false;

	public function new(type:TokenType, value:String, line:Int, col:Int, start:Int, end:Int, newlineBefore:Bool) {
		this.type = type;
		this.value = value;
		this.line = line;
		this.col = col;
		this.start = start;
		this.end = end;
		this.newlineBefore = newlineBefore;
	}
}
