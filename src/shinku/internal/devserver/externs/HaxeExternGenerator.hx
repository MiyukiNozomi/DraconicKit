package shinku.internal.devserver.externs;

import haxe.rtti.CType;
import haxe.io.Output;
import sys.io.File;
import haxe.rtti.CType.TypeInfos;
import haxe.rtti.CType.TypeTree;
import haxe.io.Error;
import shinku.std.io.SystemTools;
import haxe.io.Path;
import shinku.Console.Logger;
import sys.FileSystem;

using StringTools;

#if draconicbuilder
typedef ModuleInfo = {
	typeRoot:Array<TypeTree>
};

class HaxeExternGenerator {
	static var moduleOf:Map<String, String> = new Map();
	static var scopeParams:Array<String> = [];

	public static function generate(externsDir:String) {
		var xmlPath = FileSystem.absolutePath(Path.join([SystemTools.thisHomeDir(), "bin/shinku-project-symbols.xml"]));

		if (!FileSystem.exists(xmlPath)) {
			Logger.error("Could not locate " + xmlPath + "! is your DraconicKit installation corrupted? please rebuild!");
			throw "Bad DraconicKit installation.";
		}
		final xml = Xml.parse(sys.io.File.getContent(xmlPath)).firstElement();
		if (xml == null)
			throw Error.Custom("Couldn't parse ../bin/shinku.xml!");

		final rtti = new haxe.rtti.XmlParser();
		rtti.process(xml, "unused");
		var root = rtti.root;

		moduleOf = new Map();
		for (entry in root)
			indexModules(entry);

		var accumulator = new Map<String, ModuleInfo>();
		for (entry in root)
			generateExtern(accumulator, entry);

		for (key in accumulator.keys()) {
			var e = accumulator.get(key);
			if (e != null)
				generateExternOf(key, e, externsDir);
		}
	}

	static function generateExtern(accumulator:Map<String, ModuleInfo>, entry:TypeTree) {
		final append = (infos:TypeInfos) -> {
			var f = infos.file;
			if (!infos.path.startsWith("shinku") || f == null)
				return;

			var accEntry = accumulator.get(f);

			if (accEntry == null) {
				accEntry = {typeRoot: []};
				accumulator.set(f, accEntry);
			}
			accEntry.typeRoot.push(entry);
		}

		switch (entry) {
			case TClassdecl(c):
				append(c);
			case TTypedecl(c):
				append(c);
			case TEnumdecl(c):
				append(c);
			case TAbstractdecl(c):
				append(c);
			case TPackage(name, fp, subs):
				if (!fp.startsWith("shinku"))
					return;
				for (sub in subs)
					generateExtern(accumulator, sub);
			default:
				Logger.error("Entry not implemented: ", entry.getName());
		};
	}

	static function packageAsName(path:String) {
		return path.split('.').filter(v -> v.length > 0).slice(-1)[0];
	}

	static function indexModules(tree:TypeTree) {
		switch (tree) {
			case TPackage(_, _, subs):
				for (sub in subs)
					indexModules(sub);
			default:
				final infos = infosOf(tree);
				if (infos != null && infos.module != null)
					moduleOf.set(infos.path, infos.module);
		}
	}

	static function qualify(path:String):String {
		final module = moduleOf.get(path);
		if (module == null || module == path)
			return path;
		return module + "." + packageAsName(path);
	}

	static function refName(path:String):String {
		if (!moduleOf.exists(path) && path.indexOf(".") != -1) {
			final last = packageAsName(path);
			if (scopeParams.indexOf(last) != -1)
				return last;
		}
		return qualify(path);
	}

	static function infosOf(tree:TypeTree):Null<TypeInfos> {
		return switch (tree) {
			case TClassdecl(c): c;
			case TTypedecl(t): t;
			case TEnumdecl(e): e;
			case TAbstractdecl(a): a;
			default: null;
		}
	}

	static function packageOf(infos:TypeInfos):String {
		final m = infos.module != null ? infos.module : infos.path;
		final parts = m.split('.');
		parts.pop();
		return parts.join('.');
	}

	static function ensureDir(dir:String) {
		if (dir == "" || FileSystem.exists(dir))
			return;
		ensureDir(Path.directory(dir));
		FileSystem.createDirectory(dir);
	}

	static function hasMeta(meta:Null<MetaData>, name:String):Bool {
		if (meta == null)
			return false;
		for (m in meta)
			if (m.name == name)
				return true;
		return false;
	}

	static function writeDoc(output:Output, doc:Null<String>, indent:String) {
		if (doc == null || doc.trim().length == 0)
			return;
		output.writeString('$indent/**\n');
		for (line in doc.split("\n"))
			output.writeString('$indent ${line.trim().replace("*/", "* /")}\n');
		output.writeString('$indent**/\n');
	}

	static function writeDeclParams(output:Output, params:Null<TypeParams>) {
		if (params == null || params.length == 0)
			return;
		output.writeString('<' + params.join(", ") + '>');
	}

	static function writeTypeParams(output:Output, params:Array<CType>) {
		if (params == null || params.length == 0)
			return;
		output.writeString('<');
		var i = 0;
		for (p in params) {
			if (i++ != 0)
				output.writeString(", ");
			writeType(output, p);
		}
		output.writeString('>');
	}

	static function writePathParams(output:Output, pp:PathParams) {
		output.writeString(refName(pp.path));
		writeTypeParams(output, pp.params);
	}

	static function writeFunctionArgs(output:Output, args:Array<FunctionArgument>, asDeclaration:Bool) {
		var i = 0;
		for (a in args) {
			if (i++ != 0)
				output.writeString(", ");

			final hasName = a.name != null && a.name.length > 0;
			if (asDeclaration) {
				if (a.value != null) {
					output.writeString('${a.name}:');
					writeType(output, a.t);
					output.writeString(' = ${a.value}');
				} else {
					output.writeString((a.opt ? "?" : "") + a.name + ":");
					writeType(output, a.t);
				}
			} else if (hasName) {
				output.writeString((a.opt ? "?" : "") + a.name + ":");
				writeType(output, a.t);
			} else {
				if (a.opt)
					output.writeString("?");
				writeType(output, a.t);
			}
		}
	}

	static function writeType(output:Output, type:CType) {
		switch (type) {
			case CUnknown:
				output.writeString('Dynamic /*unknown type*/');
			case CDynamic(d):
				output.writeString('Dynamic');
				if (d != null) {
					output.writeString('<');
					writeType(output, d);
					output.writeString('>');
				}
			case CAnonymous(fields):
				{
					output.writeString('{');
					var i = 0;
					for (field in fields) {
						if (i++ != 0)
							output.writeString(", ");
						writeField(output, field);
					}
					output.writeString('}');
				}
			case CEnum(name, params):
				output.writeString(refName(name));
				writeTypeParams(output, params);
			case CClass(name, params):
				output.writeString(refName(name));
				writeTypeParams(output, params);
			case CTypedef(name, params):
				output.writeString(refName(name));
				writeTypeParams(output, params);
			case CAbstract(name, params):
				output.writeString(refName(name));
				writeTypeParams(output, params);
			case CFunction(args, ret):
				output.writeString('(');
				writeFunctionArgs(output, args, false);
				output.writeString(') -> ');
				writeType(output, ret);
		}
	}

	static function writeField(output:Output, field:ClassField) {
		if (field.doc != null)
			output.writeString('/**\n${field.doc}\n**/\n');
		if (hasMeta(field.meta, ":optional"))
			output.writeString("?");
		output.writeString(field.name + ":");
		writeType(output, field.type);
	}

	static function writeTypedef(output:Output, t:Typedef) {
		scopeParams = t.params != null ? t.params.copy() : [];
		writeDoc(output, t.doc, "");
		output.writeString("typedef " + packageAsName(t.path));
		writeDeclParams(output, t.params);
		output.writeString(" = ");
		writeType(output, t.type);
		output.writeString(";\n\n");
	}

	static function writeEnum(output:Output, e:Enumdef) {
		scopeParams = e.params != null ? e.params.copy() : [];
		writeDoc(output, e.doc, "");
		output.writeString("enum " + packageAsName(e.path));
		writeDeclParams(output, e.params);
		output.writeString(" {\n");
		for (ctor in e.constructors) {
			writeDoc(output, ctor.doc, "\t");
			output.writeString("\t" + ctor.name);
			if (ctor.args != null) {
				output.writeString("(");
				writeFunctionArgs(output, ctor.args.map(v -> ({
					name: v.name,
					opt: v.opt,
					t: v.t,
					value: null
				})), false);
				output.writeString(")");
			}
			output.writeString(";\n");
		}
		output.writeString("}\n\n");
	}

	static function writeAbstract(output:Output, a:Abstractdef) {
		scopeParams = a.params != null ? a.params.copy() : [];
		writeDoc(output, a.doc, "");
		output.writeString((hasMeta(a.meta, ":enum") ? "enum abstract " : "abstract ") + packageAsName(a.path));
		writeDeclParams(output, a.params);
		output.writeString("(");
		writeType(output, a.athis);
		output.writeString(")");
		for (f in a.from)
			if (f.field == null && f.t != null) {
				output.writeString(" from ");
				writeType(output, f.t);
			}
		for (t in a.to)
			if (t.field == null && t.t != null) {
				output.writeString(" to ");
				writeType(output, t.t);
			}
		output.writeString(" {\n\t// Members are not generated for abstracts: their implementation lives in the original module.\n}\n\n");
	}

	static function accessorName(r:Rights, isGetter:Bool):String {
		return switch (r) {
			case RNormal: "default";
			case RNo: "null";
			case RCall(_): isGetter ? "get" : "set";
			case RDynamic: "dynamic";
			default: "default";
		}
	}

	static function isMethodRights(r:Rights):Bool {
		return switch (r) {
			case RMethod: true;
			default: false;
		}
	}

	static function isDynamicRights(r:Rights):Bool {
		return switch (r) {
			case RDynamic: true;
			default: false;
		}
	}

	static function isNormalRights(r:Rights):Bool {
		return switch (r) {
			case RNormal: true;
			default: false;
		}
	}

	static function accessorFnName(r:Rights):Null<String> {
		return switch (r) {
			case RCall(m): m;
			default: null;
		}
	}

	static function writeClassField(output:Output, f:ClassField, isStatic:Bool, isInterface:Bool) {
		final indent = "\t";
		final previousScope = scopeParams;
		if (f.params != null && f.params.length > 0)
			scopeParams = previousScope.concat(f.params);
		writeDoc(output, f.doc, indent);
		output.writeString(indent);

		if (!isInterface)
			output.writeString(f.isPublic ? "public " : "private ");
		if (f.isOverride)
			output.writeString("override ");
		if (isStatic)
			output.writeString("static ");

		switch (f.type) {
			case CFunction(args, ret) if (isMethodRights(f.set) || isDynamicRights(f.set)):
				if (isDynamicRights(f.set))
					output.writeString("dynamic ");
				output.writeString("function " + f.name);
				writeDeclParams(output, f.params);
				output.writeString("(");
				writeFunctionArgs(output, args, true);
				output.writeString(")");
				if (f.name != "new") {
					output.writeString(":");
					writeType(output, ret);
				}
				output.writeString(";\n");
			default:
				if (f.isFinal) {
					output.writeString("final " + f.name);
				} else {
					output.writeString("var " + f.name);
					if (!(isNormalRights(f.get) && isNormalRights(f.set)))
						output.writeString('(${accessorName(f.get, true)}, ${accessorName(f.set, false)})');
				}
				output.writeString(":");
				writeType(output, f.type);
				output.writeString(";\n");
		}

		scopeParams = previousScope;
	}

	static function writeClass(output:Output, c:Classdef) {
		scopeParams = c.params != null ? c.params.copy() : [];
		writeDoc(output, c.doc, "");
		output.writeString((c.isInterface ? "extern interface " : "extern class ") + packageAsName(c.path));
		writeDeclParams(output, c.params);

		final superClass = c.superClass;
		if (superClass != null) {
			output.writeString(" extends ");
			writePathParams(output, superClass);
		}
		for (i in c.interfaces) {
			output.writeString(c.isInterface ? " extends " : " implements ");
			writePathParams(output, i);
		}
		output.writeString(" {\n");

		final needed = new Map<String, Bool>();
		for (f in c.fields.concat(c.statics)) {
			final g = accessorFnName(f.get);
			final s = accessorFnName(f.set);
			if (g != null)
				needed.set(g, true);
			if (s != null)
				needed.set(s, true);
		}

		final shouldWrite = (f:ClassField) -> /*f.isPublic*/ true || needed.exists(f.name);

		for (f in c.statics)
			if (shouldWrite(f))
				writeClassField(output, f, true, c.isInterface);
		for (f in c.fields)
			if (shouldWrite(f))
				writeClassField(output, f, false, c.isInterface);

		output.writeString("}\n\n");
	}

	static function generateExternOf(srcPath:String, entry:ModuleInfo, externsDir:String) {
		final destPath = Path.join([externsDir, srcPath]);
		ensureDir(Path.directory(destPath));

		Logger.debug(srcPath, "->", destPath);

		var pack = "";
		for (e in entry.typeRoot) {
			final infos = infosOf(e);
			if (infos != null) {
				pack = packageOf(infos);
				break;
			}
		}

		var output = File.write(destPath);
		output.writeString('
/**
    This module contains externs from the original file at
    ${Path.join([SystemTools.thisHomeDir(), srcPath])}
    in a mission to speed up compilation and decrease the size of the hot swapped modules.

	**DO NOT MODIFY THIS!** you wont get anywhere by doing so. file a pull request at 
	https://github.com/MiyukiNozomi/DraconicKit to change something here (or just edit your local draconickit copy)
*/        

package ${pack};

');

		for (entry in entry.typeRoot) {
			switch (entry) {
				case TTypedecl(t):
					writeTypedef(output, t);
				case TEnumdecl(e):
					writeEnum(output, e);
				case TClassdecl(c):
					writeClass(output, c);
				case TAbstractdecl(a):
					writeAbstract(output, a);
				default:
					output.writeString("// Could not generate extern for " + entry.getName() + " (not implemented.)\n\n");
			}
		}

		output.close();
	}
}
#end
