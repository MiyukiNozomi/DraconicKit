import {
  ZodAny,
  ZodArray,
  ZodBoolean,
  ZodDefault,
  ZodEnum,
  ZodNullable,
  ZodNumber,
  ZodObject,
  ZodOptional,
  ZodPromise,
  ZodRecord,
  ZodString,
  ZodStringFormat,
  ZodUnion,
  ZodVoid,
} from "zod";

/*** A MASSIVE function intended to convert runtime type definitions from zod into typescript, basically the reverse process of
 * z.infer
 */
export function zodTypeToTS(type: any, descriptedTypes: Set<string>): string {
  const existingName = type.description;
  if (existingName) {
    descriptedTypes.add(existingName);
    return existingName;
  }

  if (type instanceof ZodDefault)
    return zodTypeToTS(type.unwrap(), descriptedTypes);
  if (type instanceof ZodNumber) return "number";
  if (type instanceof ZodBoolean) return "boolean";
  if (type instanceof ZodString || type instanceof ZodStringFormat)
    return "string";
  if (type instanceof ZodVoid) return "void";
  if (type instanceof ZodOptional)
    return `${zodTypeToTS(type.unwrap() as ZodAny, descriptedTypes)} | undefined`;
  if (type instanceof ZodArray)
    return `Array<${zodTypeToTS(type.element, descriptedTypes)}>`;
  if (type instanceof ZodRecord)
    return `Record<${zodTypeToTS(
      type.keyType,
      descriptedTypes,
    )}, ${zodTypeToTS(type.valueType, descriptedTypes)}>`;
  if (type instanceof ZodEnum) {
    return `(${Object.values(type.enum)
      .map((v) => JSON.stringify(v))
      .join(" | ")})`;
  }
  if (type instanceof ZodUnion) {
    return `(${Object.values(type.options)
      .map((v) => zodTypeToTS(v, descriptedTypes))
      .join(" | ")})`;
  }
  if (type instanceof ZodNullable) {
    return `(${zodTypeToTS(type.unwrap(), descriptedTypes)} | null)`;
  }
  if (type instanceof ZodPromise) {
    return zodTypeToTS(type.unwrap(), descriptedTypes);
  }
  if (type instanceof ZodObject) {
    let fields = new Array<string>();
    const shape = (type as ZodObject<any>).shape;
    for (const key in shape) {
      fields.push(`${key}: ${zodTypeToTS(shape[key], descriptedTypes)}`);
    }
    return `{${fields.join(", ")}}`;
  }
  if (type instanceof ZodAny) return "any";
  throw new TypeError(
    "Could not create schema -> typescript declaration script! unsupported type: " +
      JSON.stringify(type),
  );
}
