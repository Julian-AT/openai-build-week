import canonicalize from "canonicalize";

import {
  RunnerFailure,
  caseResult,
  parseJsonBytesStrict,
  readFixtureFile,
  rejectedCaseResult,
  sha256Hex,
} from "./loader.mjs";

function validateIJson(value) {
  const stack = [value];
  while (stack.length > 0) {
    const current = stack.pop();
    if (typeof current === "number" && !Number.isFinite(current)) throw new RunnerFailure("numeric_out_of_range", "JCS input contains a non-finite number");
    if (typeof current === "string") {
      for (let index = 0; index < current.length; index += 1) {
        const code = current.charCodeAt(index);
        if (code >= 0xd800 && code <= 0xdbff) {
          const next = current.charCodeAt(index + 1);
          if (next < 0xdc00 || next > 0xdfff) throw new RunnerFailure("invalid_unicode", "JCS input contains an unpaired surrogate");
          index += 1;
        } else if (code >= 0xdc00 && code <= 0xdfff) {
          throw new RunnerFailure("invalid_unicode", "JCS input contains an unpaired surrogate");
        }
      }
    } else if (Array.isArray(current)) {
      stack.push(...current);
    } else if (current !== null && typeof current === "object") {
      stack.push(...Object.keys(current), ...Object.values(current));
    }
  }
}

export function canonicalizeBytes(value) {
  validateIJson(value);
  let serialized;
  try {
    serialized = canonicalize(value);
  } catch (error) {
    throw new RunnerFailure("json_parse", "RFC 8785 canonicalization failed", { cause: error });
  }
  if (typeof serialized !== "string") throw new RunnerFailure("json_parse", "RFC 8785 canonicalizer returned no JSON text");
  return Buffer.from(serialized, "utf8");
}

export function canonicalDigest(value) {
  return sha256Hex(canonicalizeBytes(value));
}

export async function executeJcsCase(fixture, fixtureCase) {
  try {
    const value = parseJsonBytesStrict(await readFixtureFile(fixture, fixtureCase.input));
    const canonicalBytes = canonicalizeBytes(value);
    const digest = sha256Hex(canonicalBytes);
    const digestBytes = Buffer.from(`${digest}\n`, "utf8");
    return caseResult(fixtureCase.case_id, "accept", null, [
      { kind: "canonical_bytes", byte_length: canonicalBytes.length, sha256: sha256Hex(canonicalBytes) },
      { kind: "digest", byte_length: digestBytes.length, sha256: sha256Hex(digestBytes), value_sha256: digest },
    ]);
  } catch (error) {
    return rejectedCaseResult(fixtureCase, error);
  }
}
