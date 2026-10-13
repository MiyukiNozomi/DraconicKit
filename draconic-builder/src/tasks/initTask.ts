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
import { modulePath, stdinInquiry } from "../io.js";
import { zodTypeToTS } from "../typeConv.js";
import {
  configSchema,
  getProjectConfig,
  type DraconicConfig,
} from "../configs/draconicConfig.js";
import { select } from "@inquirer/prompts";

import { execFileSync } from "child_process";

function generateTypescriptConfig(config: DraconicConfig) {
  writeFileSync(
    "./.shinku/tsconfig.json",
    JSON.stringify({
      compilerOptions: {
        paths: {},
        rootDirs: ["../", "../.shinku/types"],
        types: ["./.shinku/types"],
        lib: ["ESNext", "DOM", "DOM.Iterable"],
        verbatimModuleSyntax: true,
        isolatedModules: true,
        allowJs: true,
        checkJs: true,
        forceConsistentCasingInFileNames: true,
        resolveJsonModule: true,
        moduleDetection: "force",
        moduleResolution: "bundler",
        allowImportingTsExtensions: true,
        module: "esnext",
        target: "esnext",
        skipLibCheck: true,
        esModuleInterop: true,
        noEmit: true,
      },
    }),
  );
  writeFileSync(
    "./tsconfig.json",
    JSON.stringify({
      extends: "./.shinku/tsconfig.json",
      compilerOptions: {
        strict: true,
      },
      include: ["src"],
    }),
  );
}

function generateProjectConfig(withTypescriptSupport: boolean) {
  writeFileSync(
    "./dragon.config.js",
    `
    /**
 *
 * Welcome to DraconicKit!
 *
 * This is your project's config file.
 * You can also alter Svelte's Compiler options here.
 * It is not typescript (sorry) because that would create a build time dependency on it. but it's fine as long as the latter @returns isnt removed.
 *
 * Please  do not return an object that doesnt matches DraconicConfig!
 * If by any reason the auto completion isn't giving suggestions even with an empty object,
 * consider running the 'build' task of the builder. It will generate the draconic.config.d.ts file this file depends on.
 *
 * Happy coding! and may your Haxe backend adventures be full of joy.
 *
 * @returns {import("./.shinku/generated/draconic.config").DraconicConfig}
 */
export default function getServerConfig() {
  return {
    builder: ${JSON.stringify({ typescriptSupport: withTypescriptSupport })},
    server: {
      host: "0.0.0.0",
      port: 8173,
      static_dir: "static/",
    },
  };
}`,
  );
}

export async function recreateShinkusFolder(config: DraconicConfig) {
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

  if (config.builder.typescriptSupport) {
    await generateTypescriptConfig(config);
  }
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

  const withTypescriptSupport = await select({
    message: `Would you like to use typescript in your frontend? (this is an experimental option, and might not work 100% of the time).
WARNING: This will use TypeScript 6.x, not TypeScript 7, learn more here at https://typescriptdocs.com/release-notes/TypeScript%207.0 for the reason why.`,
    choices: [
      { name: "No", value: "no" },
      { name: "Yes", value: "yes" },
    ],
  });

  generateProjectConfig(withTypescriptSupport == "yes");

  const packageManager = await select({
    message: "Which package manager do you want to use?",
    // NPM is the only one actually installing dependencies on node_modules
    // for some reason when i was testing with latest pnpm, it wasnt actually putting all dependencies there.
    // I would ask readers of this code to perform their own testing, and possibly explain to me what these package managers are actually doing.
    choices: [
      { name: "npm", value: "npm" },
      /* 
      { name: "pnpm", value: "pnpm" },
      { name: "yarn", value: "yarn" },
      { name: "bun", value: "bun" },
      */
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

  const config = await getProjectConfig();
  if (!config) return;
  await recreateShinkusFolder(config);

  console.log(
    "Project created! run this script with a 'dev' param to start coding! when ready to build for production, use 'build'!",
  );
}
