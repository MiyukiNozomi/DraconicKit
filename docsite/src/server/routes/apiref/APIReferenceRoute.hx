package server.routes.apiref;

import haxe.rtti.CType;
import haxe.Json;
import haxe.rtti.CType.TypeRoot;
import shinku.http.HttpServer;
import haxe.io.Error;
import haxe.io.Path;
import haxe.rtti.CType.TypeTree;

using StringTools;

private typedef TreeNode = {
	label:String,
	children:Array<TreeNode>
}

class APIReference {
	static final ROOT_PACKAGE = "shinku";
	static final ROUTE_PREFIX = "/apiref";

	var root:TypeRoot;
	var httpServer:HttpServer;

	var tableOfContentsTree:TreeNode;

	private function new(httpServer:HttpServer) {
		this.httpServer = httpServer;
		this.tableOfContentsTree = {
			label: "shinku",
			children: []
		};
		final xml = Xml.parse(sys.io.File.getContent("../bin/shinku.xml")).firstElement();
		if (xml == null)
			throw Error.Custom("Couldn't parse ../bin/shinku.xml!");

		final rtti = new haxe.rtti.XmlParser();
		rtti.process(xml, "unused");
		this.root = rtti.root;
	}

	private function infoOf(t:TypeTree) {
		return switch t {
			case TTypedecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TClassdecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TEnumdecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TAbstractdecl(t): {path: t.path, isPrivate: t.isPrivate};
			case TPackage(name, fullPath, _): {path: fullPath, isPrivate: name.startsWith("_")};
		}
	}

	private function createRoute(t:TypeTree) {
		final basicInfo = infoOf(t);
		if (!basicInfo.path.startsWith(tableOfContentsTree.label) || basicInfo.isPrivate)
			return;
		final routename = "/docs/api/" + basicInfo.path.split('.').filter(v -> v.length > 0).join('/');

		this.httpServer.requestHandler.dynamicRouter.addDynamicRoute(routename + ".xhtml",
			new XHTMLRoute(Path.join([Main.SERVE_DIRECTORY, "/res/html/apiref/view.xhtml"]), {
				"targetInfo": describe(t),
				"tableOfContentsTree": tableOfContentsTree
			}));
	}

	static function describePathParams(p:PathParams) {
		return {
			path: p.path,
			params: p.params.map(v -> describeType(v))
		};
	}

	static function describeType(t:CType):Dynamic {
		return switch (t) {
			case CEnum(name, params): {type: "enum", name: name, params: params.map(v -> describeType(v))}
			case CClass(name, params): {type: "class", name: name, params: params.map(v -> describeType(v))}
			case CTypedef(name, params): {type: "typedef", name: name, params: params.map(v -> describeType(v))}
			case CAbstract(name, params): {type: "abstract", name: name, params: params.map(v -> describeType(v))}
			case CAnonymous(fields): {type: "anonymous", fields: fields.map(v -> describeField(v, false))}
			case CDynamic(t): {type: "dynamic", possibly: t == null ? {type: "null"} : describeType(t)}
			case CFunction(args, ret): {
					type: "function",
					args: args.map(v -> ({
						name: v.name,
						isOptional: v.opt,
						type: describeType(v.t),
						defaultValue: v.value
					})),
					ret: describeType(ret)
				}
			case CUnknown: {type: "unknown"}
		};
	}

	static function describeField(v:ClassField, isStatic:Bool):Dynamic {
		return {
			name: v.name,
			doc: v.doc,
			isStatic: isStatic,
			isFinal: v.isFinal,
			isPublic: v.isPublic,
			isOverride: v.isOverride,
			type: describeType(v.type)
		};
	};

	static function describeClass(c:Classdef) {
		return transmutate(c, {
			isFinal: c.isFinal,
			isExtern: c.isExtern,
			isInterface: c.isInterface,
			superClass: c.superClass != null ? describePathParams(c.superClass) : null,
			interfaces: c.interfaces.map(v -> describePathParams(v)),
			fields: c.fields.map(v -> describeField(v, false)).concat(c.statics.map(v -> describeField(v, true)))
		});
	}

	static function transmutate(c:TypeInfos, other:Dynamic) {
		var c = {
			path: c.path,
			doc: c.doc,
			params: c.params,
		};

		for (key in Reflect.fields(other)) {
			Reflect.setProperty(c, key, Reflect.getProperty(other, key));
		}

		return c;
	}

	static function describe(t:TypeTree):Dynamic {
		return switch t {
			case TClassdecl(c):
				{
					type: "class",
					data: describeClass(c)
				};
			case TEnumdecl(c): {
					type: "enum",
					data: transmutate(c, {
						isExtern: c.isExtern,
						constructors: c.constructors.map(v -> ({
							name: v.name,
							args: v.args != null ? v.args.map(v -> ({
								name: v.name,
								optional: v.opt,
								type: describeType(v.t)
							})) : [],
							doc: v.doc
						}))
					})
				};
			case TTypedecl(c):
				var types = new Map<String, Dynamic>();
				for (key => value in c.types) {
					types.set(key, describeType(value));
				}
				return {
					type: "typedef",
					data: transmutate(c, {
						type: describeType(c.type),
						types: types
					})
				};
			case TAbstractdecl(c):
				{
					type: "abstract class",
					data: transmutate(c, {
						impl: describeClass(c.impl),
					})
				};
			case TPackage(_, full, subs): {type: "package", data: {path: full, subs: subs.map(v -> describe(v))}};
		}
	}

	static function walk(apiRef:APIReference, entry:TypeTree, fn:(apiRef:APIReference, entry:TypeTree) -> Void) {
		fn(apiRef, entry);

		switch entry {
			case TPackage(_, _, subs):
				{
					for (e in subs)
						walk(apiRef, e, fn);
				}
			default:
		}
	}

	public static function init(httpServer:HttpServer) {
		var apiRef = new APIReference(httpServer);

		httpServer.requestHandler.dynamicRouter.addDynamicRoute("/docs/api",
			new XHTMLRoute(Path.join([Main.SERVE_DIRECTORY, "/res/html/apiref/index.xhtml"]), {tableOfContentsTree: apiRef.tableOfContentsTree}));

		for (entry in apiRef.root)
			walk(apiRef, entry, (apiRef, entry) -> {
				var basicInfo = apiRef.infoOf(entry);
				if (!basicInfo.path.startsWith(apiRef.tableOfContentsTree.label) || basicInfo.isPrivate)
					return;
				var pathname = basicInfo.path.split('.').filter(v -> v.length > 0).slice(1);
				var root = apiRef.tableOfContentsTree;
				for (i in 0...pathname.length - 1) {
					var path = pathname[i];
					var nextInChain = root.children.filter(v -> v.label == path)[0];
					if (nextInChain == null) {
						nextInChain = {
							label: path,
							children: []
						};
						root.children.push(nextInChain);
					}
					root = nextInChain;
				}
				var leaf = pathname[pathname.length - 1];
				if (root.children.filter(v -> v.label == leaf)[0] == null) {
					root.children.push({
						label: leaf,
						children: []
					});
				}
			});

		for (entry in apiRef.root)
			walk(apiRef, entry, (apiRef, entry) -> {
				apiRef.createRoute(entry);
			});
	}
}
