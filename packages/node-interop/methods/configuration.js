import z from "zod";

const configSchema = z.strictObject({
  builder: z.strictObject({
    typescriptSupport: z.boolean().default(false),
    alwaysCleanup: z.boolean().default(false),
  }),

  server: z.strictObject({
    logging: z
      .strictObject({
        debugLogs: z.boolean().default(false),
        showTimestamps: z.boolean().default(true),
        showDevRequests: z.boolean().default(false),
        useColorsInLogs: z.boolean().default(true),
      })
      .default({
        debugLogs: false,
        showTimestamps: true,
        useColorsInLogs: true,
      }),
    host: z.string().default("localhost"),
    port: z.number().int().min(1).max(65535).default(8173),
    static_dir: z.string().default("static/"),
  }),
});

export let Configuration;

export async function loadConfiguration({ filename }) {
  const module = await import(filename);
  const getServerConfig = module.default;
  if (!getServerConfig || typeof getServerConfig != "function") {
    throw new Error(
      filename + " does not export a default function named 'getServerConfig'.",
    );
  }

  let file = configSchema.safeParse(await getServerConfig());

  if (!file.success) {
    throw new Error("Could not parse config file: " + file.error);
  }

  Configuration = file.data;

  // DO NOT PASS SVELTE OPTIONS OR PLUGINS HERE!
  return {
    builder: file.data.builder,
    server: file.data.server,
  };
}
