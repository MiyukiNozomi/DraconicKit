import { z } from "zod";

const ProcessedSchema = z.object({
  code: z.string(),
  map: z.unknown().optional(),
});

const PreprocessorResultSchema = z.union([ProcessedSchema, z.undefined()]);

const MarkupPreprocessorOptionsSchema = z.object({
  /** The whole Svelte file content */
  content: z.string(),

  /** The filename of the Svelte file */
  filename: z.string().optional(),
});

const PreprocessorOptionsSchema = z.object({
  /** The script/style tag content */
  content: z.string(),

  /** The attributes on the script/style tag */
  attributes: z.record(z.string(), z.union([z.string(), z.boolean()])),

  /** The whole Svelte file content */
  markup: z.string(),

  /** The filename of the Svelte file */
  filename: z.string().optional(),
});

export const MarkupPreprocessorSchema = z.function({
  input: [MarkupPreprocessorOptionsSchema],
  output: z.promise(PreprocessorResultSchema).or(PreprocessorResultSchema),
});

export const PreprocessorSchema = z.function({
  input: [PreprocessorOptionsSchema],
  output: z.promise(PreprocessorResultSchema).or(PreprocessorResultSchema),
});

export const PreprocessorGroupSchema = z.object({
  /** Name of the preprocessor */
  name: z.string().optional(),

  /** Processes the entire Svelte file */
  markup: MarkupPreprocessorSchema.optional(),

  /** Processes style tags */
  style: PreprocessorSchema.optional(),

  /** Processes script tags */
  script: PreprocessorSchema.optional(),
});
