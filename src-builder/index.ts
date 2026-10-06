import { buildProject } from "./tasks/buildTask.js";
import { createProject } from "./tasks/initTask.js";
import { modulePath } from "./tools.js";

async function main() {
  console.log("Running at", modulePath);

  let arg = process.argv.findLast(() => true);

  if (arg == "init") {
    createProject();
  } else if (arg == "build") {
    buildProject();
  } else {
    console.log(`
    DraconicKit, Ryuu, whatever name I ended up giving it, Builder!

    Functions:

        init  - Initializes a project
        dev   - runs an active file system watcher and reloads the project as needed
        build - Builds a project for production
`);
  }
}

await main();
