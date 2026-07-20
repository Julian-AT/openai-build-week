import { createHash } from "node:crypto";

/**
 * The common wire digest representation. It is deliberately small: public
 * protocol values are JSON data only, object keys sort lexicographically, and
 * non-finite/unsafe numeric values have no canonical representation.
 */
export function canonicalJSONStringify(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

export function canonicalJSONSHA256(value: unknown): string {
  return createHash("sha256").update(canonicalJSONStringify(value), "utf8").digest("hex");
}

function canonicalize(value: unknown): unknown {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value) && Number.isSafeInteger(value))
  ) {
    return value;
  }
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value !== "object" || value === null) throw new TypeError("invalid_canonical_json");
  const object = value as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  for (const key of Object.keys(object).sort()) {
    if (key.length === 0 || key.includes("\u0000")) throw new TypeError("invalid_canonical_json");
    result[key] = canonicalize(object[key]);
  }
  return result;
}
