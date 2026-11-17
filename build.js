"use strict";

import fs, { watch } from "fs";
import path from "path";
import { spawn } from "child_process";

const DEFAULT_DEPENDENCY_REPOSITORY = "https://repo.maven.apache.org/maven2";
const DEFAULT_DEPENDENCY_DIRECTORY = "lib";

async function checkAndUpdateJavaLib({ groupId, artifactId }) {
  function extractTag(xml, tag) {
    const match = xml.match(new RegExp(`<${tag}>\\s*([^<\\s]+)\\s*</${tag}>`));
    return match?.[1];
  }

  const artifactUrl = `${DEFAULT_DEPENDENCY_REPOSITORY}/${groupId.replace(/\./g, "/")}/${artifactId}`;

  const metadataResponse = await fetch(`${artifactUrl}/maven-metadata.xml`);
  if (!metadataResponse.ok) {
    throw new Error(`Failed to fetch metadata: ${metadataResponse.status}`);
  }

  const metadata = await metadataResponse.text();
  const latest =
    extractTag(metadata, "release") ?? extractTag(metadata, "latest");

  if (!latest) {
    throw new Error(`Could not find latest version for ${artifactId}`);
  }

  await fs.promises.mkdir(DEFAULT_DEPENDENCY_DIRECTORY, { recursive: true });

  const jarName = `${artifactId}-${latest}.jar`;
  const tempFilename = path.join(DEFAULT_DEPENDENCY_DIRECTORY, jarName);

  if (fs.existsSync(tempFilename)) {
    console.log(`${artifactId} is already up to date (${latest})`);
    return;
  }

  const url = `${artifactUrl}/${latest}/${jarName}`;
  console.log(`Downloading ${artifactId} ${latest} from '${url}'...`);

  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Download failed: ${response.status}`);
  }

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length === 0) {
    throw new Error("Downloaded JAR is empty");
  }
  console.log(buffer.length);

  await fs.promises.writeFile(tempFilename, buffer);
  await fs.promises.copyFile(
    tempFilename,
    path.join(DEFAULT_DEPENDENCY_DIRECTORY, `${artifactId}.jar`),
  );

  console.log(`Installed ${artifactId} ${latest}.`);
}

let currentBuild = null;
let pendingBuild = false;

function runBuild(args) {
  return new Promise((resolve) => {
    if (currentBuild) return (pendingBuild = true);

    console.log(`\n[${new Date().toLocaleTimeString()}] Building ${args}...`);

    currentBuild = spawn("haxe", args, {
      stdio: "inherit",
    });

    currentBuild.on("error", (err) => {
      resolve();
      console.error("Failed to start build:", err.message);
    });

    currentBuild.on("close", (code) => {
      resolve();
      console.log(
        `[${new Date().toLocaleTimeString()}] Build '${args}' exited with code ${code}`,
      );

      currentBuild = null;

      if (pendingBuild) {
        pendingBuild = false;
        runBuild(args);
      }
    });
  });
}

console.log("Checking dependencies and installing..");

/*
await checkAndUpdateJavaLib({
  groupId: "org.mozilla",
  artifactId: "rhino",
});
*/

const hxmlFile = process.argv.includes("--dev")
  ? "build-dev.hxml"
  : "build.hxml";

console.log("Running build for " + hxmlFile);
await runBuild([hxmlFile]);

if (!process.argv.includes("--watch")) process.exit(0);
console.log(`Watching src for changes...`);

{
  let debounceTimer;
  watch(
    path.resolve("packages/"),
    { recursive: true },
    (eventType, filename) => {
      if (!filename) return;
      console.log(`[${eventType}] ${filename}`);

      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(async () => {
        await runBuild([hxmlFile]);
      }, 300);
    },
  );
}
