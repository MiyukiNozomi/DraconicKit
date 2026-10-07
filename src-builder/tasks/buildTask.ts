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
import { getProjectConfig } from "../draconicConfig.js";
import { TemplateHXML } from "../templates.js";
import path from "node:path";
import { execSync } from "node:child_process";
import { recreateShinkusFolder } from "./initTask.js";

function getAllServerFiles(
  rootDir: string,
  directory: string,
  routeList: Array<string>,
) {
  if (statSync(directory).isDirectory()) {
    readdirSync(directory).forEach((v) =>
      getAllServerFiles(rootDir, path.posix.join(directory, v), routeList),
    );
  } else if (path.posix.basename(directory) == "Server.hx") {
    let content = readFileSync(directory).toString();
    if (
      !content.includes("ServerHandler") ||
      !content.includes("AbstractHandler")
    ) {
      console.error(
        "Warning: Not an acceptable server.hx file at",
        directory,
        " class name is not ServerHandler or it isnt extending Abstract Handler.",
      );
      return;
    }

    let route = path.posix.dirname(directory);

    let existing = routeList.find((v) => v == route);
    if (existing) {
      console.error(
        `Warning: route ${route} has a duplicated server handler with the name: ${existing}`,
      );
      return;
    }
    routeList.push(route.substring(rootDir.length));
  }
}

function routename2Package(routename: string, asPackage = true) {
  return (
    "routes" +
    (asPackage ? "." : "/") +
    routename
      .split("/")
      .filter(Boolean)
      .map((v) => v.replace(/^\[\.*/, "").replace(/\]$/, ""))
      .join(asPackage ? "." : "/") +
    (asPackage ? ".Server.ServerHandler" : "")
  );
}

export async function buildProject(isDevMode: Boolean = false) {
  let config = await getProjectConfig();
  if (!config) return;

  let thisBuildFile = [...TemplateHXML];
  if (isDevMode) thisBuildFile.unshift("-D dev");

  await recreateShinkusFolder();

  let dynamicRouteFiles = new Array<string>();
  getAllServerFiles("src/routes", "src/routes", dynamicRouteFiles);

  mkdirSync(".shinku/generated", { recursive: true });
  writeFileSync(".shinku/build.hxml", thisBuildFile.join("\n"));
  if (existsSync(".shinku/project-transformed-src")) {
    rmSync(".shinku/project-transformed-src", { recursive: true });
  }
  mkdirSync(".shinku/project-transformed-src", { recursive: true });

  console.log("Transforming...");
  dynamicRouteFiles.map((truePath) => {
    const finalPath = path.join(
      ".shinku/project-transformed-src",
      routename2Package(truePath, false),
    );
    console.log(truePath, "->", finalPath);

    cpSync(path.posix.join("src/routes", truePath), finalPath, {
      recursive: true,
    });
  });

  // let's create the main server class

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

// dynamic route imports
${dynamicRouteFiles.map((v) => `import ${routename2Package(v)};`).join("\n")}

class ServerMain {
    static function main() {
        var server = new HttpServer(new Host(${JSON.stringify(config.server.host)}), ${config.server.port});

        // dynamic route registry goes here..
        ${dynamicRouteFiles.map((v) => `server.requestHandler.dynamicRouter.addDynamicRoute(${JSON.stringify(v)}, new ${routename2Package(v)}())`).join(";\n")};

        // finally, start the server.
        server.start();
    }
}
`,
  );

  try {
    execSync("haxe .shinku/build.hxml", {
      stdio: "inherit",
    });
    console.log("Build complete.");
  } catch {
    console.error("Build failed!");
    process.exit(-5);
  }
}
