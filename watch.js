import { watch } from "fs";
import path from "path";
import { spawn } from "child_process";

const BUILD_COMMAND = "haxe";
const BUILD_ARGS = ["build-dev-backend.hxml"];

let debounceTimer;
let currentBuild = null;
let pendingBuild = false;

function runBuild() {
  if (currentBuild) return (pendingBuild = true);

  console.log(`\n[${new Date().toLocaleTimeString()}] Building...`);

  currentBuild = spawn(BUILD_COMMAND, BUILD_ARGS, {
    stdio: "inherit",
  });

  currentBuild.on("error", (err) => {
    console.error("Failed to start build:", err.message);
  });

  currentBuild.on("close", (code) => {
    console.log(
      `[${new Date().toLocaleTimeString()}] Build exited with code ${code}`,
    );

    currentBuild = null;

    if (pendingBuild) {
      pendingBuild = false;
      runBuild();
    }
  });
}

console.log(`Watching src for changes...`);

watch(path.resolve("src/"), { recursive: true }, (eventType, filename) => {
  if (!filename) return;
  console.log(`[${eventType}] ${filename}`);

  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    runBuild();
  }, 300);
});
