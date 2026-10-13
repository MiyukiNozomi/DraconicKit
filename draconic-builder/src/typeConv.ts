import type { z } from "zod";

type Schema = z.core.$ZodType;

const IDENTIFIER = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

/**
 * Converts a zod schema into a TypeScript type expression (roughly the
 * reverse of z.infer). Schemas with a `.describe("Name")` are emitted as
 * that name and recorded in `namedTypes` so the caller can declare them.
 */
export function zodTypeToTS(schema: Schema, namedTypes: Set<string>): string {
  const toTS = (s: Schema) => zodTypeToTS(s, namedTypes);

  const name = (schema as { description?: string }).description;
  if (name) {
    namedTypes.add(name);
    return name;
  }

  const def = schema._zod.def as any;

  switch (def.type) {
    case "string":
    case "template_literal":
    case "number":
    case "boolean":
    case "bigint":
    case "date":
    case "void":
    case "null":
    case "undefined":
    case "any":
    case "unknown":
    case "never":
      return def.type;

    case "literal":
      return (def.values as unknown[])
        .map((v) => JSON.stringify(v))
        .join(" | ");

    case "enum":
      return `(${Object.values(def.entries)
        .map((v) => JSON.stringify(v))
        .join(" | ")})`;

    case "optional":
      return `(${toTS(def.innerType)} | undefined)`;
    case "nullable":
      return `(${toTS(def.innerType)} | null)`;
    case "nonoptional":
    case "default":
    case "prefault":
    case "readonly":
    case "catch":
      return toTS(def.innerType);

    case "array":
      return `Array<${toTS(def.element)}>`;
    case "tuple":
      return `[${(def.items as Schema[]).map(toTS).join(", ")}]`;
    case "set":
      return `Set<${toTS(def.valueType)}>`;
    case "map":
      return `Map<${toTS(def.keyType)}, ${toTS(def.valueType)}>`;
    case "record":
      return `Record<${toTS(def.keyType)}, ${toTS(def.valueType)}>`;

    case "union":
      return `(${(def.options as Schema[]).map(toTS).join(" | ")})`;
    case "intersection":
      return `(${toTS(def.left)} & ${toTS(def.right)})`;

    case "promise":
      return `Promise<${toTS(def.innerType)}>`;
    case "function": // TODO: render real function signatures :P
      return "(...args: any[]) => any";
    case "lazy":
      return toTS(def.getter());

    case "object": {
      const fields = Object.entries(def.shape as Record<string, Schema>).map(
        ([key, value]) => {
          const isOptional = (value as any)._zod.def.type === "optional";
          const inner = isOptional ? (value as any)._zod.def.innerType : value;
          return `${IDENTIFIER.test(key) ? key : JSON.stringify(key)}${isOptional ? "?" : ""}: ${toTS(inner)}`;
        },
      );
      return `{ ${fields.join("; ")} }`;
    }

    default:
      throw new TypeError(`zodTypeToTS: unsupported zod type "${def.type}"`);
  }
}
