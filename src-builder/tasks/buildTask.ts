import {
  mkdirSync,
  readdirSync,
  readFileSync,
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
  mapping: Map<string, string>,
) {
  if (statSync(directory).isDirectory()) {
    readdirSync(directory).forEach((v) =>
      getAllServerFiles(rootDir, path.posix.join(directory, v), mapping),
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

    let existing = mapping.get(route);
    if (existing) {
      console.error(
        `Warning: route ${route} has a duplicated server handler with the name: ${existing}`,
      );
      return;
    }
    mapping.set(
      route.substring(rootDir.length),
      ("routes/" + route.substring(rootDir.length).substring(1))
        .split("/")
        .filter((v) => v.length > 0)
        .join(".") + ".Server.ServerHandler",
    );
  }
}

export async function buildProject(isDevMode: Boolean = false) {
  let config = getProjectConfig();
  if (!config) return;

  let thisBuildFile = [...TemplateHXML];
  if (isDevMode) thisBuildFile.unshift("-D dev");

  await recreateShinkusFolder();

  let dynamicRouteFiles = new Map<string, string>();
  getAllServerFiles("src/routes", "src/routes", dynamicRouteFiles);

  let routeFilesArray = Array.from(dynamicRouteFiles);

  console.log(routeFilesArray.map((v) => `${v[0]} -> ${v[1]}`).join("\n-"));

  mkdirSync(".shinku/generated", { recursive: true });
  writeFileSync(".shinku/build.hxml", thisBuildFile.join("\n"));

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
${routeFilesArray.map((v) => `import ${v[1].substring(0, v[1].lastIndexOf("."))};`).join("\n")}

class ServerMain {
    static function main() {
        var server = new HttpServer(new Host(${JSON.stringify(config.server.host)}), ${config.server.port});

        // dynamic route registry goes here..
        ${routeFilesArray.map((v) => `server.requestHandler.addDynamicRoute(${JSON.stringify(v[0])}, new ${v[1].substring(v[1].lastIndexOf("." + 1))}())`)};

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
