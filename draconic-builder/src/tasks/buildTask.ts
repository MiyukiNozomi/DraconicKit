import { execSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import {
  compile,
  preprocess,
  type CompileError,
  type Processed,
} from "svelte/compiler";

import {
  getProjectConfig,
  type DraconicConfig,
} from "../configs/draconicConfig.js";
import { TemplateHXML } from "../templates.js";
import { directoryExplore } from "../io.js";
import { recreateShinkusFolder } from "./initTask.js";
import { tsCompile } from "../toolkit/tsc.js";

const ROUTES_DIR = "src/routes";
const SHINKU_DIR = ".shinku";
const TRANSFORMED_SRC_DIR = `${SHINKU_DIR}/project-transformed-src`;
const GENERATED_DIR = `${SHINKU_DIR}/generated`;

const HANDLER_KINDS = {
  "Server.hx": "AbstractHandler",
  "ServerPage.hx": "AbstractServerPage",
} as const;

type ClassInformation = {
  pathname: string;
  className: string;
  moduleName: string;
  extendedClassName: string | null;
};

type ParsedClass = {
  className: string | null;
  moduleName: string;
  extendedClass: string | null;
};

type SvelteRoute = {
  routename: string;
  physicalPath: string;
};

type DiscoveryResult = {
  routes: ClassInformation[];
  svelteFiles: string[];
  failed: boolean;
};

function tokenize(pathname: string): string[] {
  return readFileSync(pathname)
    .toString()
    .split("\n")
    .map((line) => line.trim())
    .flatMap((line) => line.split(" "))
    .filter((token) => token.length > 0);
}

function getClassInformation(
  pathname: string,
  expectedExtendedClass: string,
): ParsedClass {
  const tokens = tokenize(pathname);

  let className: string | null = null;
  let extendedClass: string | null = null;

  let i = 0;
  while (i < tokens.length) {
    if (tokens[i++] !== "class") continue;

    className = tokens[i++] ?? null;
    if (
      className &&
      tokens[i++] === "extends" &&
      tokens[i++] === expectedExtendedClass
    ) {
      extendedClass = expectedExtendedClass;
      break;
    }
  }

  console.log("class", className, "is extending", extendedClass);

  return {
    className,
    moduleName: path.basename(pathname).replace(".hx", ""),
    extendedClass,
  };
}

function isValidHandlerClass(
  info: ParsedClass,
  expectedExtendedClass: string,
): boolean {
  return !!info.className && info.extendedClass === expectedExtendedClass;
}

function discoverRoutes(rootDir: string, directory: string): DiscoveryResult {
  const result: DiscoveryResult = {
    routes: [],
    svelteFiles: [],
    failed: false,
  };

  const visit = (current: string) => {
    const basename = path.posix.basename(current);

    if (statSync(current).isDirectory()) {
      readdirSync(current).forEach((entry) =>
        visit(path.posix.join(current, entry)),
      );
      return;
    }

    if (basename.endsWith(".svelte")) {
      result.svelteFiles.push(current);
      return;
    }

    if (!(basename in HANDLER_KINDS)) return;

    const expectedClass = HANDLER_KINDS[basename as keyof typeof HANDLER_KINDS];
    const info = getClassInformation(current, expectedClass);

    if (!isValidHandlerClass(info, expectedClass)) {
      console.error(
        "Error: Not an acceptable Server.hx/ServerPage.hx file at",
        current,
        `
Server.hx files must have ONE class extending AbstractHandler.
ServerPage.hx files must have ONE class extending AbstractServerPage.
`,
      );
      result.failed = true;
      return;
    }

    const route = path.posix.dirname(current);

    const existing = result.routes.find(
      (r) => r.pathname === route.substring(rootDir.length),
    );
    if (existing) {
      console.error(
        `Warning: route ${route} has a duplicated server handler with the name: ${existing.className}
Cannot have both Server.hx and ServerPage.hx in the same folder.`,
      );
      return;
    }

    result.routes.push({
      pathname: route.substring(rootDir.length),
      className: info.className!,
      moduleName: info.moduleName,
      extendedClassName: info.extendedClass,
    });
  };

  visit(directory);
  return result;
}

const HAXE_IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*$/;

function routeSegments(route: ClassInformation): string[] {
  return route.pathname
    .split("/")
    .filter(Boolean)
    .map((segment) =>
      segment
        .replace(/^\[\.*/, "")
        .replace(/\]$/, "")
        .replaceAll("-", "_"),
    )
    .map((segment) => {
      if (!HAXE_IDENTIFIER.test(segment)) {
        throw (
          "This pathname " +
          route.pathname +
          "has a bad package name. DraconicKit doesnt really support routes that dont have valid haxe identifiers. sorry."
        );
      }
      return segment;
    });
}

function routeDirectory(route: ClassInformation): string {
  return ["routes", ...routeSegments(route)].join("/");
}

function routeClassName(route: ClassInformation): string {
  return [
    "routes",
    ...routeSegments(route),
    route.moduleName,
    route.className,
  ].join(".");
}

async function handleFrontendScriptFiles(
  isDevMode: boolean,
  config: DraconicConfig,
) {
  if (config.builder.typescriptSupport) {
    let tsFiles = new Array<string>();
    await directoryExplore("src", (fp, filename) => {
      if (filename.endsWith(".ts")) {
        tsFiles.push(fp);
      }
    });

    const tsConfig = JSON.parse(readFileSync("./tsconfig.json").toString());
    const files = await tsCompile(tsFiles, tsConfig);

    for (const [key, value] of Object.entries(files)) {
      const directory = path.dirname(key.substring("src".length));
      const modulePath = path.join(
        SHINKU_DIR,
        config.server.static_dir,
        "@library",
        directory,
      );
      mkdirSync(modulePath, { recursive: true });
      writeFileSync(path.join(modulePath, path.basename(key)), value);
    }
  } else {
    await directoryExplore("src", (fp, filename) => {
      if (filename.endsWith(".js")) {
        const directory = path.dirname(fp.substring("src".length));
        const modulePath = path.join(
          SHINKU_DIR,
          config.server.static_dir,
          "@library",
          directory,
        );
        mkdirSync(modulePath, { recursive: true });
        cpSync(fp, path.join(modulePath, filename));
      }
    });
  }
}

async function compileSvelteFile(
  file: string,
  isDevMode: boolean,
  config: DraconicConfig,
): Promise<SvelteRoute> {
  const src = readFileSync(file).toString();
  const preprocessorConfig = config.svelteOptions?.preprocess;
  let target: string | Processed = src;

  if (preprocessorConfig) {
    // what a cheap hack!
    const preprocessed = await preprocess(src, preprocessorConfig as any, {});
    target = preprocessed;
  }
  const result = compile(typeof target == "string" ? target : target.code, {
    dev: isDevMode,
    rootDir: path.resolve("src/"),
    generate: "client",
    filename: file,
  });

  const routename = file.substring("src/routes/".length);
  const modulePath = path.join(
    SHINKU_DIR,
    config.server.static_dir,
    "@library",
    "routes",
    routename,
  );
  mkdirSync(modulePath, { recursive: true });

  writeFileSync(path.join(modulePath, "page.js"), result.js.code);
  if (result.css) {
    writeFileSync(path.join(modulePath, "page.css"), result.css.code);
  }

  return {
    routename: path.dirname("/" + routename),
    physicalPath: modulePath,
  };
}

function isSvelteCompileError(err: unknown): err is CompileError {
  return !!err && typeof err === "object" && "code" in err && "filename" in err;
}

function buildSvelte(
  isDevMode: boolean,
  config: DraconicConfig,
  svelteFiles: string[],
): Promise<SvelteRoute[]> {
  return Promise.all(
    svelteFiles.map(async (file) => {
      try {
        return await compileSvelteFile(file, isDevMode, config);
      } catch (err) {
        if (isSvelteCompileError(err)) {
          console.log(
            "Failed to compile " +
              err.filename +
              ": " +
              err.message +
              (err.frame ? "\n" + err.frame : ""),
          );
          throw "Svelte Build Failed!";
        }
        throw err;
      }
    }),
  );
}

function prepareOutputFolders(config: DraconicConfig, isDevMode: boolean) {
  const hxml = [...TemplateHXML];
  if (isDevMode) hxml.unshift("-D dev");

  mkdirSync(GENERATED_DIR, { recursive: true });
  writeFileSync(`${SHINKU_DIR}/build.hxml`, hxml.join("\n"));

  rmSync(TRANSFORMED_SRC_DIR, { recursive: true, force: true });
  mkdirSync(TRANSFORMED_SRC_DIR, { recursive: true });

  rmSync(`${SHINKU_DIR}/static`, { recursive: true, force: true });
  cpSync(config.server.static_dir, `${SHINKU_DIR}/static`, { recursive: true });
}

function transformRouteSources(routes: ClassInformation[]) {
  console.log("Transforming...");

  if (existsSync("src/routes/ServerHooks.hx"))
    cpSync(
      path.posix.join(ROUTES_DIR, "ServerHooks.hx"),
      path.join(TRANSFORMED_SRC_DIR, "routes/ServerHooks.hx"),
      {
        recursive: true,
      },
    );

  for (const route of routes) {
    const finalPath = path.join(TRANSFORMED_SRC_DIR, routeDirectory(route));
    console.log(route.pathname, "->", finalPath);

    cpSync(path.posix.join(ROUTES_DIR, route.pathname), finalPath, {
      recursive: true,
    });
  }
}

const SET_HOOKS = "server.requestHandler.dynamicRouter.setServerHooks";
const ADD_ROUTE = "server.requestHandler.dynamicRouter.addDynamicRoute";

function buildHandlerRegistrations(routes: ClassInformation[]): string[] {
  return routes
    .filter((r) => r.extendedClassName === "AbstractHandler")
    .map(
      (r) =>
        `${ADD_ROUTE}(${JSON.stringify(r.pathname)}, new ${routeClassName(r)}())`,
    );
}

function buildSvelteRegistrations(
  routes: ClassInformation[],
  svelteRoutes: SvelteRoute[],
): string[] {
  const serverPages = routes.filter(
    (r) => r.extendedClassName === "AbstractServerPage",
  );
  const used = new Set<string>();

  const registrations = svelteRoutes.map((svelte) => {
    const page = serverPages.find((r) => r.pathname === svelte.routename);
    if (page) used.add(page.pathname);

    const serverPage = page ? `new ${routeClassName(page)}()` : "null";
    return `${ADD_ROUTE}(${JSON.stringify(svelte.routename)}, new SvelteRouter(${serverPage}, ${JSON.stringify(svelte.physicalPath)}))`;
  });

  const orphan = serverPages.find((r) => !used.has(r.pathname));
  if (orphan) {
    throw (
      "We have a ServerPage.hx but no +page.svelte! ServerPage.hx is located at: " +
      orphan.pathname
    );
  }

  return registrations;
}

function joinStatements(statements: string[]): string {
  return statements.length > 0 ? statements.join(";\n\t\t") + ";" : "";
}

function generateServerMain(
  config: DraconicConfig,
  routes: ClassInformation[],
  svelteRoutes: SvelteRoute[],
): string {
  let routeImports = routes
    .map((r) => `import ${routeClassName(r)};`)
    .join("\n");

  let hooksLine = "";

  if (existsSync("src/routes/ServerHooks.hx")) {
    const hooksFile = getClassInformation(
      "src/routes/ServerHooks.hx",
      "AbstractServerHooks",
    );

    if (hooksFile.extendedClass != "AbstractServerHooks")
      throw "File src/ServerHooks.hx must have a class extending AbstractServerHooks..";

    routeImports =
      `import routes.ServerHooks.${hooksFile.className};\n` + routeImports;
    hooksLine = `${SET_HOOKS}(new routes.ServerHooks.${hooksFile.className}());`;
  }

  const handlers = joinStatements(buildHandlerRegistrations(routes));
  const svelte = joinStatements(buildSvelteRegistrations(routes, svelteRoutes));

  return `
/**
 *  GENERATED CLASS, PLEASE DO NOT MODIFY OR CALL MANUALLY!
*/  
 
import sys.net.Host;
 
import ryuu.Configuration;
import ryuu.http.HttpServer;
 
import ryuu.handling.RequestHandler;
 
import ryuu.internal.SvelteRoute;
#if dev
import ryuu.internal.ESModuleRoute;
#end
 
// dynamic route imports
${routeImports}
 
class ServerMain {
  static function main() {
    #if dev
		  Configuration.WorkingDirectory = ${JSON.stringify(path.resolve(".shinku"))};
    #end
		Configuration.StaticDirectory = ${JSON.stringify(config.server.static_dir)};
    Configuration.SvelteBaseHTML = ${JSON.stringify(readFileSync("src/app.html").toString())};
 
    var server = new HttpServer(new Host(${JSON.stringify(config.server.host)}), ${config.server.port});
 
    #if dev
      server.requestHandler.dynamicRouter.addDynamicRoute("/@module/[...path]", new ESModuleRoute());
    #end
  
    ${hooksLine}
    // dynamic route registry goes here..
    ${handlers}
    // svelte page routes go here..
    ${svelte}
 
    // finally, start the server.
    server.start();
  }
}
`;
}

function cleanHaxeOutput(output: string): string {
  return output.replaceAll(`${TRANSFORMED_SRC_DIR}/`, "src/");
}

function compileHaxe() {
  try {
    const output = execSync("haxe project.hxml", { encoding: "utf8" });
    console.log(cleanHaxeOutput(output));
    console.log(`=======================
Build complete.
=======================
`);
  } catch (error) {
    const err = error as {
      stdout?: Buffer | string;
      stderr?: Buffer | string;
      status?: number;
    };

    const output = cleanHaxeOutput(
      `${err.stdout?.toString() ?? ""}${err.stderr?.toString() ?? ""}`,
    );

    if (output) console.error(output);
    console.error("Build failed!");
    process.exit(1);
  }
}

export async function buildProject(isDevMode: boolean = false) {
  const config = await getProjectConfig();
  if (!config) return;

  await recreateShinkusFolder(config);

  const { routes, svelteFiles, failed } = discoverRoutes(
    ROUTES_DIR,
    ROUTES_DIR,
  );
  if (failed) throw "BUILD FAILED";

  prepareOutputFolders(config, isDevMode);
  transformRouteSources(routes);

  console.log("Svelte sources:", "\n" + svelteFiles.join("\n"));
  console.log("Building..");
  const svelteRoutes = await buildSvelte(isDevMode, config, svelteFiles);

  await handleFrontendScriptFiles(isDevMode, config);

  writeFileSync(
    `${GENERATED_DIR}/ServerMain.hx`,
    generateServerMain(config, routes, svelteRoutes),
  );

  compileHaxe();
}
