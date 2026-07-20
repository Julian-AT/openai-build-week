import { canonicalizeBytes } from "./canonical-json.mjs";
import {
  caseResult,
  parseJsonBytesStrict,
  RunnerFailure,
  readFixtureFile,
  readFixtureInternal,
  rejectedCaseResult,
  sha256Hex,
} from "./loader.mjs";
import { validateContractValue } from "./schema-validator.mjs";

export const RRFP_FIXED_HEADER_BYTES = 24;
export const RRFP_JSON_MAX_BYTES = 65_536;
export const RRFP_PAYLOAD_MAX_BYTES = 16_777_216;

function requireWire(condition, rejectionClass, message) {
  if (!condition) throw new RunnerFailure(rejectionClass, message);
}

function requireSequence(value) {
  requireWire(
    Number.isSafeInteger(value) && value >= 0,
    "wire_sequence",
    "capture sequence is not an exact nonnegative integer",
  );
  return BigInt(value);
}

export function encodeWireFrame(header, payloadBytes) {
  const payload = Buffer.from(payloadBytes);
  const headerBytes = canonicalizeBytes(header);
  requireWire(
    headerBytes.length <= RRFP_JSON_MAX_BYTES,
    "wire_length",
    "JCS header exceeds RRFP limit",
  );
  requireWire(
    payload.length <= RRFP_PAYLOAD_MAX_BYTES,
    "wire_length",
    "payload exceeds RRFP limit",
  );
  requireWire(
    header.image?.payload?.byte_length === payload.length,
    "wire_length",
    "payload length duplicate does not agree",
  );
  requireWire(
    header.payload_sha256 === sha256Hex(payload),
    "digest_mismatch",
    "payload digest does not agree",
  );
  const fixed = Buffer.alloc(RRFP_FIXED_HEADER_BYTES);
  fixed.write("RRFP", 0, "ascii");
  fixed.writeUInt8(1, 4);
  fixed.writeUInt8(0, 5);
  fixed.writeUInt16BE(0, 6);
  fixed.writeUInt32BE(headerBytes.length, 8);
  fixed.writeUInt32BE(payload.length, 12);
  fixed.writeBigUInt64BE(requireSequence(header.capture_sequence), 16);
  return Buffer.concat([fixed, headerBytes, payload]);
}

export function decodeWireFrame(fixture, bytes) {
  const wire = Buffer.from(bytes);
  requireWire(
    wire.length >= RRFP_FIXED_HEADER_BYTES,
    "wire_truncated",
    "RRFP fixed header is truncated",
  );
  requireWire(
    wire.subarray(0, 4).equals(Buffer.from("RRFP", "ascii")),
    "wire_magic",
    "RRFP magic is invalid",
  );
  requireWire(
    wire.readUInt8(4) === 1 && wire.readUInt8(5) === 0,
    "wire_version",
    "RRFP version is unsupported",
  );
  requireWire(wire.readUInt16BE(6) === 0, "wire_flags", "RRFP flags must be zero");
  const headerLength = wire.readUInt32BE(8);
  const payloadLength = wire.readUInt32BE(12);
  const sequence = wire.readBigUInt64BE(16);
  requireWire(
    headerLength <= RRFP_JSON_MAX_BYTES && payloadLength <= RRFP_PAYLOAD_MAX_BYTES,
    "wire_length",
    "RRFP declared length exceeds limit",
  );
  requireWire(
    wire.length >= RRFP_FIXED_HEADER_BYTES + headerLength,
    "wire_truncated",
    "RRFP JSON header is truncated",
  );

  const headerBytes = wire.subarray(
    RRFP_FIXED_HEADER_BYTES,
    RRFP_FIXED_HEADER_BYTES + headerLength,
  );
  let header;
  try {
    header = parseJsonBytesStrict(headerBytes);
  } catch (error) {
    if (error instanceof RunnerFailure)
      throw new RunnerFailure(
        "wire_length",
        "RRFP JSON-header length does not delimit one complete header",
      );
    throw error;
  }
  validateContractValue(fixture, "CON-001", header);
  requireWire(
    canonicalizeBytes(header).equals(headerBytes),
    "wire_length",
    "RRFP JSON header is not exact RFC 8785 JCS bytes",
  );
  requireWire(
    header.image?.payload?.byte_length === payloadLength,
    "wire_length",
    "RRFP payload-length duplicates disagree",
  );
  requireWire(
    requireSequence(header.capture_sequence) === sequence,
    "wire_sequence",
    "RRFP capture-sequence duplicates disagree",
  );

  const expectedLength = RRFP_FIXED_HEADER_BYTES + headerLength + payloadLength;
  requireWire(wire.length >= expectedLength, "wire_truncated", "RRFP payload is truncated");
  requireWire(wire.length === expectedLength, "wire_trailing_bytes", "RRFP has trailing bytes");
  const payload = wire.subarray(RRFP_FIXED_HEADER_BYTES + headerLength);
  requireWire(
    header.payload_sha256 === sha256Hex(payload),
    "digest_mismatch",
    "RRFP payload SHA-256 mismatch",
  );
  return { header, payload };
}

function parseWireHex(bytes) {
  const text = bytes.toString("utf8");
  requireWire(
    /^[0-9a-f]+\n$/.test(text) && (text.length - 1) % 2 === 0,
    "wire_length",
    "wire oracle is not lowercase even-length hex with one newline",
  );
  return Buffer.from(text.slice(0, -1), "hex");
}

function applyWireMutations(source, mutations) {
  let value = Buffer.from(source);
  for (const mutation of mutations) {
    if (mutation.op === "replace_byte") {
      requireWire(
        Number.isInteger(mutation.offset) &&
          mutation.offset >= 0 &&
          mutation.offset < value.length &&
          /^[0-9a-fA-F]{2}$/.test(mutation.value_hex),
        "wire_length",
        "invalid replace-byte mutation",
      );
      value[mutation.offset] = Number.parseInt(mutation.value_hex, 16);
    } else if (mutation.op === "replace_u32be") {
      requireWire(
        Number.isInteger(mutation.offset) &&
          mutation.offset >= 0 &&
          mutation.offset + 4 <= value.length,
        "wire_length",
        "invalid u32 mutation",
      );
      value.writeUInt32BE(mutation.value, mutation.offset);
    } else if (mutation.op === "replace_u64be") {
      requireWire(
        Number.isInteger(mutation.offset) &&
          mutation.offset >= 0 &&
          mutation.offset + 8 <= value.length,
        "wire_length",
        "invalid u64 mutation",
      );
      value.writeBigUInt64BE(BigInt(mutation.value), mutation.offset);
    } else if (mutation.op === "append_hex") {
      requireWire(
        /^(?:[0-9a-fA-F]{2})+$/.test(mutation.value_hex),
        "wire_length",
        "invalid append mutation",
      );
      value = Buffer.concat([value, Buffer.from(mutation.value_hex, "hex")]);
    } else if (mutation.op === "truncate") {
      requireWire(
        Number.isInteger(mutation.byte_length) && mutation.byte_length >= 0,
        "wire_length",
        "invalid truncate mutation",
      );
      value = value.subarray(0, mutation.byte_length);
    } else {
      throw new RunnerFailure("wire_length", "unsupported wire mutation operation");
    }
  }
  return value;
}

export async function executeWireCase(fixture, fixtureCase) {
  try {
    const descriptor = parseJsonBytesStrict(await readFixtureFile(fixture, fixtureCase.input));
    let wire;
    if (fixtureCase.case_kind === "wire_bytes") {
      const header = parseJsonBytesStrict(
        await readFixtureInternal(fixture, descriptor.header_source),
      );
      requireWire(
        /^(?:[0-9a-fA-F]{2})+$/.test(descriptor.payload_hex),
        "wire_length",
        "payload is not valid hexadecimal",
      );
      wire = encodeWireFrame(header, Buffer.from(descriptor.payload_hex, "hex"));
      decodeWireFrame(fixture, wire);
      const output = Buffer.from(`${wire.toString("hex")}\n`, "utf8");
      return caseResult(fixtureCase.case_id, "accept", null, [
        { kind: "wire_bytes", byte_length: output.length, sha256: sha256Hex(output) },
      ]);
    }
    if (fixtureCase.case_kind !== "wire_mutation")
      throw new RunnerFailure("wire_length", "unsupported wire fixture case kind");
    wire = parseWireHex(await readFixtureInternal(fixture, descriptor.base));
    decodeWireFrame(fixture, applyWireMutations(wire, descriptor.mutations ?? []));
    return caseResult(fixtureCase.case_id, "accept");
  } catch (error) {
    return rejectedCaseResult(fixtureCase, error);
  }
}
