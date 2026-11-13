import { watch } from "fs";
import path from "path";
import { spawn } from "child_process";

let currentBuild = null;
let pendingBuild = false;

function runBuild(args) {
  if (currentBuild) return (pendingBuild = true);

  console.log(`\n[${new Date().toLocaleTimeString()}] Building ${args}...`);

  currentBuild = spawn("haxe", args, {
    stdio: "inherit",
  });

  currentBuild.on("error", (err) => {
    console.error("Failed to start build:", err.message);
  });

  currentBuild.on("close", (code) => {
    console.log(
      `[${new Date().toLocaleTimeString()}] Build '${args}' exited with code ${code}`,
    );

    currentBuild = null;

    if (pendingBuild) {
      pendingBuild = false;
      runBuild(args);
    }
  });
}

console.log(`Watching src for changes...`);

{
  let debounceTimer;
  watch(path.resolve("src/"), { recursive: true }, (eventType, filename) => {
    if (!filename) return;
    console.log(`[${eventType}] ${filename}`);

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      runBuild(["build-dev-backend.hxml"]);
    }, 300);
  });
}

{
  let debounceTimer;
  watch(
    path.resolve("shinkujs/src"),
    { recursive: true },
    (eventType, filename) => {
      if (!filename) return;
      console.log(`[${eventType}] ${filename}`);

      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        runBuild(["shinkujs/build.hxml"]);
      }, 300);
    },
  );
}
