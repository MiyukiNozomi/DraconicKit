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

export async function stdinSelect(question: string, options: string[]) {
  console.log(question);

  options.forEach((option, i) => {
    console.log(`  ${i + 1}) ${option}`);
  });

  while (true) {
    const answer = await stdinInquiry("Choose an option:");

    const index = Number(answer) - 1;

    if (Number.isInteger(index) && index >= 0 && index < options.length) {
      return options[index];
    }

    console.log("Invalid choice. Please choose one of the numbers above.");
  }
}
