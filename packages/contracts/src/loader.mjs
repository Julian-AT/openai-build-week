import { createHash } from "node:crypto";
import { readFile, realpath, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

export const MAX_DOCUMENT_DEPTH = 64;
export const MAX_FILE_BYTES = 33_554_432;
export const MAX_CASES = 2_048;
export const MAX_PATH_BYTES = 240;

const ARCHIVE_PATH =
  /^(?!\/)(?![A-Za-z]:)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*\\)[A-Za-z0-9_-][A-Za-z0-9._-]*(?:\/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$/;
const MODULE_REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const REGISTERED_SCHEMAS = new Map([
  ["CON-001", ["urn:reroom:schema:frame-packet:1", "docs/contracts/frame-packet.schema.json"]],
  ["CON-002", ["urn:reroom:schema:rrcap-manifest:1", "docs/contracts/rrcap-manifest.schema.json"]],
  ["CON-003", ["urn:reroom:schema:scene-state:1", "docs/contracts/scene-state.schema.json"]],
  ["CON-004", ["urn:reroom:schema:edit-artifacts:1", "docs/contracts/edit-artifacts.schema.json"]],
  ["CON-005", ["urn:reroom:schema:transaction:1", "docs/contracts/transaction.schema.json"]],
]);

export class RunnerFailure extends Error {
  constructor(rejectionClass, message) {
    super(message);
    this.name = "RunnerFailure";
    this.rejectionClass = rejectionClass;
  }
}

export function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export async function readBytesBounded(filePath, maximum = MAX_FILE_BYTES) {
  let metadata;
  try {
    metadata = await stat(filePath);
  } catch (error) {
    throw new RunnerFailure("invalid_path", "referenced file is unavailable", { cause: error });
  }
  if (!metadata.isFile() || metadata.size > maximum) {
    throw new RunnerFailure("invalid_path", "referenced file is not a bounded regular file");
  }
  const bytes = await readFile(filePath);
  if (bytes.length !== metadata.size) {
    throw new RunnerFailure("digest_mismatch", "referenced file changed while being read");
  }
  return bytes;
}

function syntaxFailure(message) {
  return new RunnerFailure("json_parse", message);
}

export function parseJsonBytesStrict(bytes, { maxDepth = MAX_DOCUMENT_DEPTH } = {}) {
  let source;
  try {
    source = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (error) {
    throw new RunnerFailure("invalid_unicode", "JSON is not valid UTF-8", { cause: error });
  }
  if (source.charCodeAt(0) === 0xfeff) {
    throw syntaxFailure("JSON must not contain a byte-order mark");
  }

  let index = 0;
  const whitespace = () => {
    while (index < source.length) {
      const code = source.charCodeAt(index);
      if (code !== 0x09 && code !== 0x0a && code !== 0x0d && code !== 0x20) return;
      index += 1;
    }
  };
  const requireDepth = (depth) => {
    if (depth > maxDepth) throw syntaxFailure("JSON nesting exceeds the configured limit");
  };
  const parseHex = () => {
    const digits = source.slice(index, index + 4);
    if (!/^[0-9a-fA-F]{4}$/.test(digits)) throw syntaxFailure("invalid Unicode escape");
    index += 4;
    return Number.parseInt(digits, 16);
  };
  const parseString = () => {
    if (source[index] !== '"') throw syntaxFailure("expected JSON string");
    index += 1;
    let result = "";
    while (index < source.length) {
      const character = source[index++];
      if (character === '"') return result;
      if (character.charCodeAt(0) < 0x20) throw syntaxFailure("unescaped control character");
      if (character !== "\\") {
        const code = character.charCodeAt(0);
        if (code >= 0xd800 && code <= 0xdfff) {
          throw new RunnerFailure("invalid_unicode", "JSON contains an unpaired Unicode surrogate");
        }
        result += character;
        continue;
      }
      if (index >= source.length) throw syntaxFailure("unterminated JSON escape");
      const escapeCharacter = source[index++];
      const simple = {
        '"': '"',
        "\\": "\\",
        "/": "/",
        b: "\b",
        f: "\f",
        n: "\n",
        r: "\r",
        t: "\t",
      };
      if (Object.hasOwn(simple, escapeCharacter)) {
        result += simple[escapeCharacter];
        continue;
      }
      if (escapeCharacter !== "u") throw syntaxFailure("invalid JSON escape");
      const first = parseHex();
      if (first >= 0xdc00 && first <= 0xdfff) {
        throw new RunnerFailure("invalid_unicode", "JSON contains an unpaired low surrogate");
      }
      if (first >= 0xd800 && first <= 0xdbff) {
        if (source.slice(index, index + 2) !== "\\u") {
          throw new RunnerFailure("invalid_unicode", "JSON contains an unpaired high surrogate");
        }
        index += 2;
        const second = parseHex();
        if (second < 0xdc00 || second > 0xdfff) {
          throw new RunnerFailure("invalid_unicode", "JSON contains an invalid surrogate pair");
        }
        result += String.fromCodePoint(0x10000 + ((first - 0xd800) << 10) + second - 0xdc00);
      } else {
        result += String.fromCharCode(first);
      }
    }
    throw syntaxFailure("unterminated JSON string");
  };

  const parseValue = (depth) => {
    requireDepth(depth);
    whitespace();
    const character = source[index];
    if (character === '"') return parseString();
    if (character === "{") {
      index += 1;
      const value = {};
      const keys = new Set();
      whitespace();
      if (source[index] === "}") {
        index += 1;
        return value;
      }
      while (true) {
        whitespace();
        const key = parseString();
        if (keys.has(key))
          throw new RunnerFailure("duplicate_name", "JSON object contains a duplicate member name");
        keys.add(key);
        whitespace();
        if (source[index++] !== ":") throw syntaxFailure("expected ':' after object member name");
        value[key] = parseValue(depth + 1);
        whitespace();
        const delimiter = source[index++];
        if (delimiter === "}") return value;
        if (delimiter !== ",") throw syntaxFailure("expected ',' or '}' in object");
      }
    }
    if (character === "[") {
      index += 1;
      const value = [];
      whitespace();
      if (source[index] === "]") {
        index += 1;
        return value;
      }
      while (true) {
        value.push(parseValue(depth + 1));
        whitespace();
        const delimiter = source[index++];
        if (delimiter === "]") return value;
        if (delimiter !== ",") throw syntaxFailure("expected ',' or ']' in array");
      }
    }
    for (const [literal, value] of [
      ["true", true],
      ["false", false],
      ["null", null],
    ]) {
      if (source.startsWith(literal, index)) {
        index += literal.length;
        return value;
      }
    }
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(source.slice(index));
    if (!match) throw syntaxFailure("invalid JSON value");
    index += match[0].length;
    const value = Number(match[0]);
    if (!Number.isFinite(value))
      throw new RunnerFailure("numeric_out_of_range", "JSON number is not finite");
    return value;
  };

  const value = parseValue(1);
  whitespace();
  if (index !== source.length) throw syntaxFailure("trailing data after JSON value");
  return value;
}

export async function readJsonStrict(filePath, options) {
  return parseJsonBytesStrict(await readBytesBounded(filePath, options?.maxBytes), options);
}

export function validateArchivePath(relativePath) {
  if (
    typeof relativePath !== "string" ||
    Buffer.byteLength(relativePath, "utf8") > MAX_PATH_BYTES ||
    !ARCHIVE_PATH.test(relativePath)
  ) {
    throw new RunnerFailure("invalid_path", "unsafe archive-relative path");
  }
}

export async function resolveContained(
  base,
  relativePath,
  { archivePath = true, containmentRoot = base } = {},
) {
  if (archivePath) validateArchivePath(relativePath);
  if (typeof relativePath !== "string" || relativePath.includes("\0")) {
    throw new RunnerFailure("invalid_path", "invalid file reference");
  }
  try {
    const [root, candidate] = await Promise.all([
      realpath(containmentRoot),
      realpath(path.resolve(base, relativePath)),
    ]);
    const relation = path.relative(root, candidate);
    if (
      relation === "" ||
      (!relation.startsWith(`..${path.sep}`) && relation !== ".." && !path.isAbsolute(relation))
    ) {
      return candidate;
    }
  } catch (error) {
    throw new RunnerFailure("invalid_path", "file reference cannot be resolved safely", {
      cause: error,
    });
  }
  throw new RunnerFailure("invalid_path", "file reference escapes its allowed root");
}

export async function readFixtureFile(fixture, reference) {
  const filePath = await resolveContained(fixture.fixtureRoot, reference.relative_path);
  const bytes = await readBytesBounded(
    filePath,
    Math.min(MAX_FILE_BYTES, reference.byte_length + 1),
  );
  if (bytes.length !== reference.byte_length || sha256Hex(bytes) !== reference.sha256) {
    throw new RunnerFailure(
      "digest_mismatch",
      "fixture file does not match its immutable reference",
    );
  }
  return bytes;
}

export async function readFixtureInternal(fixture, relativePath, base = fixture.fixtureRoot) {
  const filePath = await resolveContained(base, relativePath, {
    archivePath: false,
    containmentRoot: fixture.repoRoot,
  });
  return readBytesBounded(filePath);
}

function createAjv() {
  const ajv = new Ajv2020({
    allErrors: true,
    allowUnionTypes: true,
    strictSchema: true,
    strictTypes: false,
    strictTuples: false,
  });
  addFormats(ajv);
  return ajv;
}

export async function loadFixture(manifestPath, { repoRoot } = {}) {
  const absoluteManifest = path.resolve(manifestPath);
  const root = path.resolve(repoRoot ?? MODULE_REPO_ROOT);
  const manifestBytes = await readBytesBounded(absoluteManifest);
  const manifest = parseJsonBytesStrict(manifestBytes);
  const manifestSchema = await readJsonStrict(path.join(root, "fixtures/manifest.schema.json"));
  const validate = createAjv().compile(manifestSchema);
  if (!validate(manifest))
    throw new RunnerFailure(
      "schema_validation",
      "fixture manifest does not satisfy FixtureManifestV1",
    );
  if (manifest.cases.length > MAX_CASES)
    throw new RunnerFailure("schema_validation", "fixture contains too many cases");
  const caseIds = manifest.cases.map(({ case_id: caseId }) => caseId);
  if (
    new Set(caseIds).size !== caseIds.length ||
    caseIds.some((caseId, index) => index > 0 && caseIds[index - 1] >= caseId)
  ) {
    throw new RunnerFailure(
      "semantic_invariant",
      "fixture case IDs must be unique and strictly lexicographic",
    );
  }

  const schemas = new Map();
  for (const reference of manifest.schema_hashes) {
    const registered = REGISTERED_SCHEMAS.get(reference.contract_id);
    if (
      !registered ||
      registered[0] !== reference.schema_id ||
      registered[1] !== reference.relative_path
    ) {
      throw new RunnerFailure(
        "schema_validation",
        "fixture schema registry tuple is not canonical",
      );
    }
    const schemaPath = await resolveContained(root, reference.relative_path);
    const schemaBytes = await readBytesBounded(schemaPath);
    if (sha256Hex(schemaBytes) !== reference.sha256)
      throw new RunnerFailure("digest_mismatch", "frozen schema digest mismatch");
    const schema = parseJsonBytesStrict(schemaBytes);
    if (schema.$id !== reference.schema_id)
      throw new RunnerFailure("schema_validation", "frozen schema ID mismatch");
    schemas.set(reference.contract_id, schema);
  }

  const fixture = {
    repoRoot: root,
    fixtureRoot: path.dirname(absoluteManifest),
    manifestPath: absoluteManifest,
    manifestBytes,
    manifestSha256: sha256Hex(manifestBytes),
    manifest,
    schemas,
  };
  for (const fixtureCase of manifest.cases) {
    await readFixtureFile(fixture, fixtureCase.input);
    for (const artifact of fixtureCase.expected.artifacts) await readFixtureFile(fixture, artifact);
  }
  return fixture;
}

function decodePointer(pointer) {
  if (pointer === "") return [];
  if (typeof pointer !== "string" || !pointer.startsWith("/"))
    throw new RunnerFailure("schema_validation", "invalid mutation pointer");
  return pointer
    .slice(1)
    .split("/")
    .map((part) => part.replaceAll("~1", "/").replaceAll("~0", "~"));
}

export function applyJsonMutations(source, mutations) {
  const value = structuredClone(source);
  for (const mutation of mutations) {
    if (!["add", "replace"].includes(mutation.op))
      throw new RunnerFailure("schema_validation", "unsupported JSON mutation operation");
    const parts = decodePointer(mutation.pointer);
    if (parts.length === 0)
      throw new RunnerFailure("schema_validation", "root mutation is not supported");
    let target = value;
    for (const part of parts.slice(0, -1)) {
      if (target === null || typeof target !== "object" || !(part in target))
        throw new RunnerFailure("schema_validation", "mutation pointer does not resolve");
      target = target[part];
    }
    const key = parts.at(-1);
    if (
      mutation.op === "replace" &&
      (target === null || typeof target !== "object" || !(key in target))
    ) {
      throw new RunnerFailure("schema_validation", "replace mutation target is absent");
    }
    target[key] = structuredClone(mutation.value);
  }
  return value;
}

export function caseResult(caseId, verdict, rejectionClass = null, outputArtifacts = []) {
  return {
    case_id: caseId,
    verdict,
    rejection_class: rejectionClass,
    output_artifacts: outputArtifacts,
  };
}

export function rejectedCaseResult(fixtureCase, error) {
  if (!(error instanceof RunnerFailure)) throw error;
  return caseResult(fixtureCase.case_id, "reject", error.rejectionClass, []);
}
