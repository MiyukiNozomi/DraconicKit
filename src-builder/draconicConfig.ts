import { existsSync, readFileSync } from "node:fs";
import z from "zod";

export const configSchema = z.strictObject({
  builder: z.strictObject({}),
  server: z.strictObject({
    host: z.string().optional().default("localhost"),
    port: z.number().min(1).max(65535).optional().default(6173),
    static_dir: z.string().optional().default("static/"),
  }),
});

export function getProjectConfig() {
  if (!existsSync("./dragon.config.json")) {
    console.log(
      "You are not in a ryuu project. Run this script with a 'init' param to create one.",
    );
    return null;
  }

  let file;
  try {
    file = configSchema.safeParse(
      JSON.parse(readFileSync("dragon.config.json").toString()),
    );
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
