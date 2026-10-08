import path from "path";
import readline from "readline";
import { fileURLToPath } from "url";

export let modulePath = (() => {
  let modulePath = path.dirname(fileURLToPath(import.meta.url));
  modulePath = modulePath.substring(0, modulePath.lastIndexOf("/"));
  return modulePath;
})();

export function stdinInquiry(question: String) {
  return new Promise<boolean>((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    rl.question(question + " [Y/n] ", (answer) => {
      const normalized = answer.trim().toLowerCase();
      rl.close();
      if (normalized === "" || normalized === "y" || normalized === "yes") {
        resolve(true);
      } else {
        resolve(false);
      }
    });
  });
}
