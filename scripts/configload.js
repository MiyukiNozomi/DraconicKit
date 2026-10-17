import z from "zod";

// TODO: do schema parsing on the Haxe side and not here.

const configSchema = z.strictObject({
  builder: z.strictObject({
    typescriptSupport: z.boolean().default(false),
  }),

  server: z.strictObject({
    logging: z
      .strictObject({
        debugLogs: z.boolean().default(false),
        showTimestamps: z.boolean().default(true),
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

let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  raw += c;
});
process.stdin.on("end", async () => {
  try {
    const { filename } = JSON.parse(raw);

    let file;
    try {
      const module = await import(filename);
      const getServerConfig = module.default;
      if (!getServerConfig || typeof getServerConfig != "function") {
        throw new Error(
          filename +
            " does not export a default function named 'getServerConfig'.",
        );
      }
      file = configSchema.safeParse(await getServerConfig());
    } catch (err) {
      throw err;
    }

    if (!file.success) {
      throw new Error("Could not parse config file: " + file.error);
    }

    console.log(JSON.stringify(file.data));
    process.exit(0);
  } catch (e) {
    console.error("Configuration processing failed: ", e);
    process.exit(1);
  }
});
