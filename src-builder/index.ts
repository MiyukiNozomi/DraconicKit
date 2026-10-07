import { buildProject } from "./tasks/buildTask.js";
import { createProject } from "./tasks/initTask.js";
import { modulePath } from "./tools.js";

async function main() {
  console.log("Running at", modulePath);

  let arg = process.argv.findLast(() => true);

  if (arg == "init") {
    await createProject();
  } else if (arg == "build") {
    await buildProject(true);
  } else {
    console.log(`
    DraconicKit, DraconicKit, whatever name I ended up giving it, Builder!

    Functions:

        init  - Initializes a project
        dev   - runs an active file system watcher and reloads the project as needed
        build - Builds a project for production
`);
  }
}

try {
  await main();
} catch (err) {
  console.log(err);
  process.exit(-5);
}
