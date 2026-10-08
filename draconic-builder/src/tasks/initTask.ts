import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import path from "path";
import { modulePath, stdinInquiry } from "../tools.js";
import { zodTypeToTS } from "../typeConv.js";
import { configSchema } from "../draconicConfig.js";
import { select } from "@inquirer/prompts";

import { execFileSync } from "child_process";

export async function recreateShinkusFolder() {
  if (existsSync("./.shinku"))
    rmSync("./.shinku", { recursive: true, force: true });

  mkdirSync("./.shinku", { recursive: true });
  symlinkSync(
    path.join(modulePath, "../src/"),
    path.resolve("./", ".shinku/server-impl"),
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
  const basedir = path.join(modulePath, "../template-project");
  readdirSync(basedir).forEach((v) =>
    cpSync(path.join(basedir, v), path.join("./", v), { recursive: true }),
  );

  const packageManager = await select({
    message: "Which package manager do you want to use?",
    choices: [
      { name: "npm", value: "npm" },
      { name: "pnpm", value: "pnpm" },
      { name: "yarn", value: "yarn" },
      { name: "bun", value: "bun" },
    ],
  });

  const command = packageManager === "npm" ? "install" : "add";

  const ourSvelteVersion = JSON.parse(
    readFileSync(path.join(modulePath, "package.json")).toString(),
  ).dependencies?.svelte;

  execFileSync(
    packageManager,
    [command, ourSvelteVersion ? `svelte@${ourSvelteVersion}` : "svelte"],
    {
      stdio: "inherit",
    },
  );

  // Force it to be ESM
  const packageJson = JSON.parse(readFileSync("./package.json", "utf8"));
  packageJson.type = "module";
  writeFileSync("./package.json", JSON.stringify(packageJson, null, 2) + "\n");

  await recreateShinkusFolder();

  console.log(
    "Project created! run this script with a 'dev' param to start coding! when ready to build for production, use 'build'!",
  );
}
