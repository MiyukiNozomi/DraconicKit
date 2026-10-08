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
import { getProjectConfig, type DraconicConfig } from "../draconicConfig.js";
import { TemplateHXML } from "../templates.js";
import path from "node:path";
import { execSync } from "node:child_process";
import { recreateShinkusFolder } from "./initTask.js";

import { compile, type CompileError } from "svelte/compiler";

type ClassInformation = {
  pathname: string;
  className: string;
  moduleName: String;
  extendedClassName: string | null;
};

function getClassInformation(pathname: string, expectedExtendedClass: string) {
  const tokens = readFileSync(pathname)
    .toString()
    .split("\n")
    .map((v) => v.trim())
    .flatMap((v) => v.split(" ").filter((v) => v.length > 0))
    .filter((v) => v.length > 0);

  let className = null as string | null;
  let extendedClass = null as string | null;

  let i = 0;
  while (i < tokens.length) {
    if (tokens[i++] == "class") {
      className = tokens[i++] ?? null;
      if (
        className &&
        tokens[i++] == "extends" &&
        expectedExtendedClass == tokens[i++]
      ) {
        extendedClass = expectedExtendedClass;
        break;
      }
      console.log(className, extendedClass);
    }
  }

  console.log("class", className, "is extending", extendedClass);
  return {
    className,
    moduleName: path.basename(pathname).replace(".hx", ""),
    extendedClass,
  };
}

let hasGetAllServerFilesFailed = false;

function getAllServerFiles(
  rootDir: string,
  directory: string,
  routeList: Array<ClassInformation>,
  svelteFiles: Array<String>,
) {
  let basename = path.posix.basename(directory);

  if (statSync(directory).isDirectory()) {
    readdirSync(directory).forEach((v) =>
      getAllServerFiles(
        rootDir,
        path.posix.join(directory, v),
        routeList,
        svelteFiles,
      ),
    );
  } else if (basename.endsWith(".svelte")) {
    svelteFiles.push(directory);
  } else if (basename == "Server.hx" || basename == "ServerPage.hx") {
    const classInfo = getClassInformation(
      directory,
      basename == "Server.hx" ? "AbstractHandler" : "AbstractServerPage",
    );

    if (
      !classInfo.className ||
      (basename == "Server.hx" &&
        classInfo.extendedClass != "AbstractHandler") ||
      (basename == "ServerPage.hx" &&
        classInfo.extendedClass != "AbstractServerPage")
    ) {
      console.error(
        "Error: Not an acceptable Server.hx/ServerPage.hx file at",
        directory,
        `
Server.hx files must have ONE class extending AbstractHandler.
ServerPage.hx files must have ONE class extending AbstractServerPage.
`,
      );
      hasGetAllServerFilesFailed = true;
      return;
    }

    let route = path.posix.dirname(directory);

    let existing = routeList.find((v) => v.pathname == route);
    if (existing) {
      console.error(
        `Warning: route ${route} has a duplicated server handler with the name: ${existing}`,
      );
      return;
    }

    routeList.push({
      pathname: route.substring(rootDir.length),
      className: classInfo.className,
      moduleName: classInfo.moduleName,
      extendedClassName: classInfo.extendedClass,
    });
  }
}

function routename2Package(clazz: ClassInformation, asPackage = true) {
  return (
    "routes" +
    (asPackage ? "." : "/") +
    clazz.pathname
      .split("/")
      .filter(Boolean)
      .map((v) =>
        v
          .replace(/^\[\.*/, "")
          .replace(/\]$/, "")
          .replaceAll("-", "_"),
      )
      .filter((v) => {
        if (!v.match(/^[A-Za-z_][A-Za-z0-9_]*$/))
          throw (
            "This pathname " +
            clazz.pathname +
            "has a bad package name. DraconicKit doesnt really support routes that dont have valid haxe identifiers. sorry."
          );
        return true;
      })
      .join(asPackage ? "." : "/") +
    (asPackage ? "." + clazz.moduleName + "." + clazz.className : "")
  );
}

function buildSvelte(
  isDevMode: boolean,
  config: DraconicConfig,
  svelteFiles: Array<string>,
) {
  let pathnames = new Array<{ routename: string; physicalPath: string }>();
  for (const file of svelteFiles) {
    try {
      const result = compile(readFileSync(file).toString(), {
        dev: isDevMode,
        rootDir: path.resolve("src/"),
        generate: "client",
        filename: file,
      });

      let routename = file.substring("src/routes/".length);
      const thisModulePath = path.join(
        ".shinku",
        config.server.static_dir,
        "@svelte",
        routename,
      );
      mkdirSync(thisModulePath, { recursive: true });

      writeFileSync(path.join(thisModulePath, "page.js"), result.js.code);
      if (result.css)
        writeFileSync(path.join(thisModulePath, "page.css"), result.css.code);
      //console.log(result);

      let rt = path.dirname("/" + routename);
      pathnames.push({
        routename: rt,
        physicalPath: thisModulePath,
      });
    } catch (err) {
      if (err && typeof err == "object" && `code` in err && `filename` in err) {
        let other = err as CompileError;

        console.log(
          "Failed to compile " +
            other.filename +
            ": " +
            other.message +
            (other.frame ? "\n" + other.frame : ""),
        );
        throw "Svelte Build Failed!";
      }
      throw err;
    }
  }
  return pathnames;
}

export async function buildProject(isDevMode: boolean = false) {
  let config = await getProjectConfig();
  if (!config) return;

  let thisBuildFile = [...TemplateHXML];
  if (isDevMode) thisBuildFile.unshift("-D dev");

  await recreateShinkusFolder();

  let dynamicRouteFiles = new Array<ClassInformation>();
  let svelteFiles = new Array<string>();
  getAllServerFiles("src/routes", "src/routes", dynamicRouteFiles, svelteFiles);

  if (hasGetAllServerFilesFailed) throw "BUILD FAILED";

  mkdirSync(".shinku/generated", { recursive: true });
  writeFileSync(".shinku/build.hxml", thisBuildFile.join("\n"));
  if (existsSync(".shinku/project-transformed-src")) {
    rmSync(".shinku/project-transformed-src", { recursive: true });
  }
  mkdirSync(".shinku/project-transformed-src", { recursive: true });

  rmSync(".shinku/static", { recursive: true, force: true });
  cpSync(config.server.static_dir, ".shinku/static", { recursive: true });

  console.log("Transforming...");
  dynamicRouteFiles.map((truePath) => {
    const finalPath = path.join(
      ".shinku/project-transformed-src",
      routename2Package(truePath, false),
    );
    console.log(truePath, "->", finalPath);

    cpSync(path.posix.join("src/routes", truePath.pathname), finalPath, {
      recursive: true,
    });
  });
  console.log("Svelte sources:", "\n" + svelteFiles.join("\n"));
  console.log("Building..");
  const svelteRouteFiles = buildSvelte(isDevMode, config, svelteFiles);

  // let's create the main server class

  const svelteRoutes = svelteRouteFiles
    .map((v) => {
      return `server.requestHandler.dynamicRouter.addDynamicRoute(${JSON.stringify(v.routename)}, new SvelteRouter(null, ${JSON.stringify(v.physicalPath)}))`;
    })
    .join(";\n\t\t");

  const dynamicRoutes = dynamicRouteFiles
    .map((v) => {
      if (v.extendedClassName == "AbstractHandler")
        return `server.requestHandler.dynamicRouter.addDynamicRoute(${JSON.stringify(v.pathname)}, new ${routename2Package(v)}())`;
      return null;
    })
    .filter((v) => v)
    .join(";\n\t\t");

  writeFileSync(
    ".shinku/generated/ServerMain.hx",
    `
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
${dynamicRouteFiles.map((v) => `import ${routename2Package(v)};`).join("\n")}

class ServerMain {
  static function main() {
    #if dev
		  Configuration.WorkingDirectory = ".shinku";
    #end
		Configuration.StaticDirectory = ${JSON.stringify(config.server.static_dir)};
    Configuration.SvelteBaseHTML = ${JSON.stringify(readFileSync("src/app.html").toString())};

    var server = new HttpServer(new Host(${JSON.stringify(config.server.host)}), ${config.server.port});

    #if dev
      server.requestHandler.dynamicRouter.addDynamicRoute("/@module/[...path]", new ESModuleRoute());
    #end

    // dynamic route registry goes here..
    ${dynamicRoutes}${dynamicRoutes.length > 0 ? ";" : ""}
    // svelte page routes go here..
    ${svelteRoutes}${svelteRoutes.length > 0 ? ";" : ""}

    // finally, start the server.
    server.start();
  }
}
`,
  );

  try {
    const output = execSync("haxe .shinku/build.hxml", {
      encoding: "utf8",
    });

    console.log(output.replaceAll(".shinku/project-transformed-src/", "src/"));
    console.log("Build complete.");
  } catch (error) {
    const err = error as {
      stdout?: Buffer | string;
      stderr?: Buffer | string;
      status?: number;
    };

    const stdout = err.stdout?.toString() ?? "";
    const stderr = err.stderr?.toString() ?? "";

    const output = `${stdout}${stderr}`.replaceAll(
      ".shinku/project-transformed-src/",
      "src/",
    );

    if (output) {
      console.error(output);
    }

    console.error("Build failed!");
    process.exit(1);
  }
}
