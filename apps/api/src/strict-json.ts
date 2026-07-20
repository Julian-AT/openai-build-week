import { TextDecoder } from "node:util";

const MAX_JSON_DEPTH = 16;

/** Parse an RFC 8259 JSON byte sequence without lossy UTF-8 or key overwrites. */
export function parseJSONBytesStrict(bytes: Uint8Array): unknown {
  let source: string;
  try {
    source = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new SyntaxError("JSON is not valid UTF-8");
  }
  if (source.charCodeAt(0) === 0xfeff) {
    throw new SyntaxError("JSON must not contain a byte-order mark");
  }

  let index = 0;
  const fail = (message: string): never => {
    throw new SyntaxError(message);
  };
  const whitespace = (): void => {
    while (index < source.length) {
      const code = source.charCodeAt(index);
      if (code !== 0x09 && code !== 0x0a && code !== 0x0d && code !== 0x20) return;
      index += 1;
    }
  };
  const requireDepth = (depth: number): void => {
    if (depth > MAX_JSON_DEPTH) fail("JSON nesting exceeds the configured limit");
  };
  const validateSurrogates = (value: string): void => {
    for (let position = 0; position < value.length; position += 1) {
      const code = value.charCodeAt(position);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = value.charCodeAt(position + 1);
        if (next < 0xdc00 || next > 0xdfff) fail("JSON contains an unpaired surrogate");
        position += 1;
      } else if (code >= 0xdc00 && code <= 0xdfff) {
        fail("JSON contains an unpaired surrogate");
      }
    }
  };
  const parseString = (): string => {
    if (source[index] !== '"') fail("expected JSON string");
    const start = index;
    index += 1;
    while (index < source.length) {
      const code = source.charCodeAt(index);
      if (code === 0x22) {
        index += 1;
        const decoded: unknown = JSON.parse(source.slice(start, index));
        if (typeof decoded !== "string") throw new SyntaxError("expected JSON string");
        validateSurrogates(decoded);
        return decoded;
      }
      if (code < 0x20) fail("unescaped control character in JSON string");
      if (code === 0x5c) {
        index += 1;
        const escapeCharacter = source[index];
        if (escapeCharacter === undefined) throw new SyntaxError("unterminated JSON escape");
        if (escapeCharacter === "u") {
          const digits = source.slice(index + 1, index + 5);
          if (!/^[0-9a-fA-F]{4}$/u.test(digits)) fail("invalid Unicode escape");
          index += 5;
          continue;
        }
        if (!['"', "\\", "/", "b", "f", "n", "r", "t"].includes(escapeCharacter)) {
          fail("invalid JSON escape");
        }
        index += 1;
        continue;
      }
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = source.charCodeAt(index + 1);
        if (next < 0xdc00 || next > 0xdfff) fail("JSON contains an unpaired surrogate");
        index += 2;
        continue;
      }
      if (code >= 0xdc00 && code <= 0xdfff) fail("JSON contains an unpaired surrogate");
      index += 1;
    }
    return fail("unterminated JSON string");
  };

  const parseValue = (depth: number): unknown => {
    requireDepth(depth);
    whitespace();
    const character = source[index];
    if (character === '"') return parseString();
    if (character === "{") {
      index += 1;
      const value: Record<string, unknown> = {};
      const names = new Set<string>();
      whitespace();
      if (source[index] === "}") {
        index += 1;
        return value;
      }
      while (true) {
        whitespace();
        const name = parseString();
        if (names.has(name)) fail("JSON object contains a duplicate member name");
        names.add(name);
        whitespace();
        if (source[index] !== ":") fail("expected ':' after JSON member name");
        index += 1;
        const member = parseValue(depth + 1);
        Object.defineProperty(value, name, {
          value: member,
          enumerable: true,
          configurable: true,
          writable: true,
        });
        whitespace();
        const delimiter = source[index];
        index += 1;
        if (delimiter === "}") return value;
        if (delimiter !== ",") fail("expected ',' or '}' in JSON object");
      }
    }
    if (character === "[") {
      index += 1;
      const value: unknown[] = [];
      whitespace();
      if (source[index] === "]") {
        index += 1;
        return value;
      }
      while (true) {
        value.push(parseValue(depth + 1));
        whitespace();
        const delimiter = source[index];
        index += 1;
        if (delimiter === "]") return value;
        if (delimiter !== ",") fail("expected ',' or ']' in JSON array");
      }
    }
    for (const [literal, value] of [
      ["true", true],
      ["false", false],
      ["null", null],
    ] as const) {
      if (source.startsWith(literal, index)) {
        index += literal.length;
        return value;
      }
    }
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/u.exec(
      source.slice(index),
    );
    if (!match) return fail("invalid JSON value");
    index += match[0].length;
    const value = Number(match[0]);
    if (!Number.isFinite(value)) return fail("JSON number is outside the finite range");
    return value;
  };

  const value = parseValue(1);
  whitespace();
  if (index !== source.length) fail("trailing data after JSON value");
  return value;
}
