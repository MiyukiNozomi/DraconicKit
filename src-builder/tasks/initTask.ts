import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import path from "path";
import { modulePath, stdinInquiry } from "../tools.js";
import { zodTypeToTS } from "../typeConv.js";
import { configSchema } from "../draconicConfig.js";

export async function recreateShinkusFolder() {
  if (existsSync("./.shinku"))
    rmSync("./.shinku", { recursive: true, force: true });

  mkdirSync("./.shinku", { recursive: true });
  symlinkSync(
    path.join(modulePath, "src/"),
    path.resolve("./", ".shinku/server-impl"),
    process.platform == "win32" ? "junction" : "dir",
  );
  symlinkSync(
    path.resolve("src"),
    path.resolve("./", ".shinku/src"),
    process.platform == "win32" ? "junction" : "dir",
  );

  mkdirSync("./.shinku/generated", { recursive: true });
  writeFileSync(
    "./.shinku/generated/draconic.config.d.ts",
    `export declare interface DraconicConfig ${zodTypeToTS(configSchema, new Set())}`,
  );
}

export async function createProject() {
  if (readdirSync("./").length > 0) {
    if (!(await stdinInquiry("Directory not empty, proceed?"))) {
      return;
    }
  }

  // lets create the project now..
  const basedir = path.join(modulePath, "template-project");
  readdirSync(basedir).forEach((v) =>
    cpSync(path.join(basedir, v), path.join("./", v), { recursive: true }),
  );

  await recreateShinkusFolder();

  console.log(
    "Project created! run this script with a 'dev' param to start coding! when ready to build for production, use 'build'!",
  );
}
