import path from "node:path";

import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

import {
  RunnerFailure,
  applyJsonMutations,
  caseResult,
  parseJsonBytesStrict,
  readFixtureFile,
  readFixtureInternal,
  rejectedCaseResult,
  sha256Hex,
} from "./loader.mjs";

const VERSION_FIELDS = ["protocol_version", "format_version", "schema_version"];

function validatorFor(fixture, contractId) {
  fixture.validators ??= new Map();
  if (!fixture.validators.has(contractId)) {
    const schema = fixture.schemas.get(contractId);
    if (!schema) throw new RunnerFailure("schema_validation", "contract schema is absent from fixture registry");
    const ajv = new Ajv2020({ allErrors: true, allowUnionTypes: true, strictSchema: true, strictTypes: false, strictTuples: false });
    addFormats(ajv);
    fixture.validators.set(contractId, ajv.compile(schema));
  }
  return fixture.validators.get(contractId);
}

function classifySchemaErrors(errors) {
  if (errors.some(({ keyword, params }) => keyword === "additionalProperties" && params?.additionalProperty === "unknown")) return "unknown_property";
  const error = errors[0] ?? {};
  const location = error.instancePath ?? "";
  if (VERSION_FIELDS.some((field) => location.endsWith(`/${field}`))) return "unsupported_contract_version";
  if (/\/(?:relative_path|packet_path|file_path)$/.test(location)) return "invalid_path";
  if (/\/(?:scene_id|session_id|frame_id|object_id|artifact_id|transaction_id|authority_id|revision_branch_id)$/.test(location)) return "invalid_identity";
  if (["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"].includes(error.keyword)) return "numeric_out_of_range";
  return "schema_validation";
}

function contractIdFor(relativePath) {
  const name = path.basename(relativePath);
  if (name.startsWith("con001.")) return "CON-001";
  if (name.startsWith("con002.")) return "CON-002";
  if (name.startsWith("con003.")) return "CON-003";
  if (name.startsWith("con004.")) return "CON-004";
  if (name.startsWith("con005.")) return "CON-005";
  throw new RunnerFailure("schema_validation", "fixture does not identify a registered contract");
}

function rejectUnsupportedVersion(value) {
  for (const field of VERSION_FIELDS) {
    if (Object.hasOwn(value, field) && value[field] !== "1.0.0") {
      throw new RunnerFailure("unsupported_contract_version", "exact contract version 1.0.0 is required");
    }
  }
}

function validateSemanticInvariants(contractId, value) {
  if (contractId === "CON-005" && value.revision_authority) {
    const prefix = value.revision_authority.kind === "native_device" ? "device_" : "gateway_";
    if (typeof value.revision_authority.authority_id === "string" && !value.revision_authority.authority_id.startsWith(prefix)) {
      throw new RunnerFailure("semantic_invariant", "revision authority kind and authority ID disagree");
    }
  }
  if (contractId === "CON-005" && value.commit) {
    if (value.commit.authority_id !== value.revision_authority.authority_id || value.commit.revision_branch_id !== value.revision_authority.revision_branch_id) {
      throw new RunnerFailure("semantic_invariant", "commit authority must equal revision authority");
    }
    if (value.commit.compare_and_swap_base_revision !== value.base_scene_revision || value.commit.committed_scene_revision !== value.base_scene_revision + 1) {
      throw new RunnerFailure("semantic_invariant", "commit revision does not satisfy compare-and-swap rules");
    }
    if (value.preview && value.commit.confirmation.preview_id !== value.preview.preview_id) {
      throw new RunnerFailure("semantic_invariant", "confirmation is not bound to the transaction preview");
    }
  }
}

export function validateContractValue(fixture, contractId, value) {
  rejectUnsupportedVersion(value);
  validateSemanticInvariants(contractId, value);
  const validate = validatorFor(fixture, contractId);
  if (!validate(value)) throw new RunnerFailure(classifySchemaErrors(validate.errors ?? []), "contract schema validation failed");
}

async function executeCompatibilityCase(fixture, descriptor) {
  if (descriptor.migration === "named_1.0_to_1.1" && descriptor.reader_version === "1.1.0" && descriptor.source_version === "1.0.0" && descriptor.representable === true) {
    const bytes = await readFixtureInternal(fixture, descriptor.source);
    validateContractValue(fixture, "CON-001", parseJsonBytesStrict(bytes));
    return;
  }
  throw new RunnerFailure("unsupported_contract_version", "no lossless named compatibility migration applies");
}

export async function executeContractCase(fixture, fixtureCase) {
  try {
    const inputBytes = await readFixtureFile(fixture, fixtureCase.input);
    if (fixtureCase.case_kind === "json_instance") {
      const value = parseJsonBytesStrict(inputBytes);
      validateContractValue(fixture, contractIdFor(fixtureCase.input.relative_path), value);
      return caseResult(fixtureCase.case_id, "accept");
    }
    if (fixtureCase.case_kind !== "json_mutation") throw new RunnerFailure("schema_validation", "unsupported contract fixture case kind");
    const descriptor = parseJsonBytesStrict(inputBytes);
    if (descriptor.migration) {
      await executeCompatibilityCase(fixture, descriptor);
      return caseResult(fixtureCase.case_id, "accept");
    }
    const baseBytes = await readFixtureInternal(fixture, descriptor.base);
    const value = applyJsonMutations(parseJsonBytesStrict(baseBytes), descriptor.mutations ?? []);
    const contractId = contractIdFor(descriptor.base);
    validateContractValue(fixture, contractId, value);
    if (descriptor.payload !== undefined) {
      if (!/^(?:[0-9a-fA-F]{2})+$/.test(descriptor.payload)) throw new RunnerFailure("schema_validation", "payload fixture is not hexadecimal");
      const payload = Buffer.from(descriptor.payload, "hex");
      if (value.image?.payload?.byte_length !== payload.length) throw new RunnerFailure("wire_length", "payload length does not match contract metadata");
      if (value.payload_sha256 !== sha256Hex(payload)) throw new RunnerFailure("digest_mismatch", "payload digest does not match exact bytes");
    }
    return caseResult(fixtureCase.case_id, "accept");
  } catch (error) {
    return rejectedCaseResult(fixtureCase, error);
  }
}
