import path from "path";
import { compile, preprocess } from "svelte/compiler";
import { Configuration } from "./configuration.js";

export async function compileSvelte({
  isDevMode,
  src,
  filename,
  rootDir,
  withHotswapSupport,
}) {
  let target = src;

  if (Configuration.svelte?.preprocessorConfig) {
    const preprocessed = await preprocess(
      target,
      Configuration.svelte.preprocessorConfig,
      {},
    );
    target = preprocessed;
  }

  return compile(typeof target == "string" ? target : target.code, {
    dev: isDevMode,
    rootDir: path.resolve(rootDir),
    generate: "client",
    filename: filename,
    hmr: withHotswapSupport,
  });
}
