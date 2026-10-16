import path from "path";
import { compile, preprocess } from "svelte/compiler";
/**
 *
 * Expected input:
 *
 * {
 *    src: string,
 *    filename: string,
 *    preprocessorConfig: any | null,
 *    rootDir: string
 * }
 */

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  raw += c;
});
process.stdin.on("end", async () => {
  try {
    const args = JSON.parse(raw);
    let target = args.src;
    if (args.preprocessorConfig) {
      const preprocessed = await preprocess(
        target,
        args.preprocessorConfig,
        {},
      );
      target = preprocessed;
    }
    const result = compile(typeof target == "string" ? target : target.code, {
      dev: args.isDevMode,
      rootDir: path.resolve(args.rootDir),
      generate: "client",
      filename: args.filename,
    });
    console.log(JSON.stringify(result));
    process.exit(0);
  } catch (e) {
    console.error("Invalid JSON: ", e);
    process.exit(1);
  }
});
