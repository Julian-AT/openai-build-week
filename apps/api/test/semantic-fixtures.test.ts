import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { test } from "bun:test";

import type { ModelProposalResult } from "@reroom/ai";

import {
  createProposalService,
  type SemanticProposalEnvelope,
} from "../src/proposal-service.ts";
import type { ProposalRequest } from "../src/protocol.ts";

interface SemanticFixtureCase {
  case_id: string;
  expected_verdict: "accept" | "reject";
  now_utc: string;
  envelope_uuid: string;
  request: ProposalRequest;
  model_result: {
    response_id: string;
    output: unknown;
  };
  expected_envelope: SemanticProposalEnvelope | null;
}

interface SemanticFixtureSet {
  schema_version: "1.0.0";
  fixture_id: "FX-SEMANTIC-PROPOSAL-001";
  fixture_revision: "rev-001";
  contract_id: "CON-006";
  contract_schema_sha256: string;
  cases: SemanticFixtureCase[];
}

test("checked-in CON-006 vectors stay immutable and executable", async () => {
  const fixtureURL = new URL(
    "../../../fixtures/semantic-proposals/1.0.0/rev-001/cases.json",
    import.meta.url,
  );
  const schemaURL = new URL("../../../docs/contracts/semantic-proposal.schema.json", import.meta.url);
  const fixtures = JSON.parse(await readFile(fixtureURL, "utf8")) as SemanticFixtureSet;
  const schemaBytes = await readFile(schemaURL);

  assert.deepEqual(Object.keys(fixtures), [
    "schema_version",
    "fixture_id",
    "fixture_revision",
    "contract_id",
    "contract_schema_sha256",
    "cases",
  ]);
  assert.equal(fixtures.schema_version, "1.0.0");
  assert.equal(fixtures.fixture_id, "FX-SEMANTIC-PROPOSAL-001");
  assert.equal(fixtures.contract_id, "CON-006");
  assert.equal(
    fixtures.contract_schema_sha256,
    createHash("sha256").update(schemaBytes).digest("hex"),
  );

  const caseIDs = fixtures.cases.map((fixture) => fixture.case_id);
  assert.deepEqual(caseIDs, [...caseIDs].sort());
  assert.equal(new Set(caseIDs).size, caseIDs.length);

  for (const fixture of fixtures.cases) {
    const service = createProposalService({
      modelClient: {
        generate: async (): Promise<ModelProposalResult> => ({
          responseID: fixture.model_result.response_id,
          output: fixture.model_result.output,
        }),
      },
      now: () => new Date(fixture.now_utc),
      randomUUID: () => fixture.envelope_uuid,
    });

    if (fixture.expected_verdict === "accept") {
      const envelope = await service.propose(fixture.request, new AbortController().signal);
      assert.deepEqual(envelope, fixture.expected_envelope, fixture.case_id);
    } else {
      assert.equal(fixture.expected_envelope, null, fixture.case_id);
      await assert.rejects(
        service.propose(fixture.request, new AbortController().signal),
        /invalid_model_output/u,
        fixture.case_id,
      );
    }
  }
});
