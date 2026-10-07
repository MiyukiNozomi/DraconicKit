import { existsSync } from "node:fs";
import path from "node:path";
import z from "zod";

export const configSchema = z.strictObject({
  builder: z.strictObject({}),
  server: z.strictObject({
    host: z.string().optional().default("localhost"),
    port: z.number().min(1).max(65535).optional().default(6173),
    static_dir: z.string().optional().default("static/"),
  }),
});

export async function getProjectConfig() {
  if (!existsSync("./dragon.config.js")) {
    console.log(
      "You are not in a ryuu project. Run this script with a 'init' param to create one.",
    );
    return null;
  }

  let file;
  try {
    const module = await import(path.resolve("./dragon.config.js"));
    const getServerConfig = module.default;
    if (!getServerConfig || typeof getServerConfig != "function") {
      throw new Error(
        "dragon.config.js does not export a default function named 'getServerConfig'.",
      );
    }
    file = configSchema.safeParse(await getServerConfig());
  } catch (err) {
    console.log(err);
    console.log("Could not load project config.");
    return null;
  }

  if (!file.data || file.error) {
    console.log("Could not parse config file: " + file.error);
    return null;
  }

  return file.data;
}
