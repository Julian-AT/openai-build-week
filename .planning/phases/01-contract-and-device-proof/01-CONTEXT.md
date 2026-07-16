# Phase 1: Contract and Device Proof - Context

**Gathered:** 2026-07-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish one executable contract and coordinate vocabulary across Swift, JavaScript, and Python, and prove the signed portrait-only base-iPhone path without rear-LiDAR semantics. This phase produces contract/coordinate fixtures, a minimal reusable Mode A seed, and real GATE-002/GATE-013 evidence. It does not implement editing, learned providers, the production compositor, or Mode B0 features.

</domain>

<decisions>
## Implementation Decisions

### Supported orientations
- **D-01:** P0 Mode A officially supports portrait orientation only.
- **D-02:** When the phone is held sideways, ARKit tracking remains alive, but capture and commit are gated and the UI coaches the user back to portrait.
- **D-03:** If the phone rotates away from portrait during a capture attempt, reject that attempt explicitly, preserve the AR session, and coach a retry.
- **D-04:** GATE-002 physical evidence covers portrait pass cases and a landscape negative/coaching case; all rotation/crop transforms remain covered by synthetic fixtures.

### Device-proof app lifecycle
- **D-05:** The signed minimal device-proof app becomes the Mode A production seed after GATE-013 passes.
- **D-06:** Phase 1 keeps that seed deliberately narrow: portrait gating, permissions, ARKit tracking and planes, and minimal hash-valid FramePacket capture only. Edit UI and provider integration remain out of scope.
- **D-07:** The proof surface is a compact diagnostic checklist with machine-readable evidence export.
- **D-08:** Diagnostic controls remain debug/internal-only in the same app target and are excluded from shipping UI.

### Golden fixture ownership
- **D-09:** Canonical vectors live in one top-level, language-neutral fixture corpus organized by contract/version and RR policy.
- **D-10:** Checked-in declarative inputs plus expected bytes and digests are authoritative. Generators are reproducible tools, not the oracle.
- **D-11:** Valid and invalid fixtures use stable case IDs; invalid cases declare the expected rejection class rather than only pass/fail.
- **D-12:** A fixture revision is accepted only when Swift, JavaScript, and Python agree and the result digests are recorded. Changes create a new immutable fixture revision.

### Evidence and gate approval
- **D-13:** Git contains sanitized manifests, checksums, reports, and tool/device versions. Raw video, screenshots, and logs remain outside Git behind opaque evidence IDs and digests.
- **D-14:** GATE-002 and GATE-013 become green only after automated checks pass and a human explicitly signs the operator checklist.
- **D-15:** Evidence records include device model, OS, Xcode/build revision, capability flags, and signing result while redacting device UUIDs, team IDs, accounts, and user data.
- **D-16:** A failed physical gate is recorded RED with exact evidence. Dependent mobile work stops; only independent contract or B0 work may continue.

### the agent's Discretion
The planner may choose internal module names, test runners, and implementation libraries within these decisions, provided exact compatible versions, license evidence, canonical contracts, and required fallbacks are preserved.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authority and phase scope
- `docs/canonical/README.md` — authority order and human-locked decisions.
- `.planning/ROADMAP.md` — Phase 1 goal, requirements, gates, and success criteria.
- `.planning/REQUIREMENTS.md` — `NFR-COORD-001`, `NFR-CONTRACT-001`, and `OPS-DEVICE-001` acceptance evidence.
- `docs/canonical/PRD.md` — normative requirement statements and fallbacks.
- `docs/canonical/DEVELOPMENT_STRATEGY.md` — S0 sequencing, evidence, and recovery boundary.

### Coordinates and physical-device proof
- `docs/adr/ADR-002-native-iphone-and-web-split.md` — native Mode A boundary and shared-contract requirement.
- `docs/adr/ADR-003-arkit-authority-and-coordinates.md` — ARKit authority and RR-COORD-1 decisions.
- `docs/adr/ADR-005-realitykit-first-compositor.md` — provisional renderer boundary; no compositor selection is made in Phase 1.
- `docs/canonical/MASTER_TECHNICAL_SPEC.md` §4 — coordinate/capture convention and rejection rules.
- `docs/canonical/TEST_AND_EVALUATION_PLAN.md` — `FX-CONTRACT-001`, `FX-JCS-001`, `FX-COORD-001`, `TST-COORD-001/002`, and `TST-DEVICE-001/002`.
- `docs/canonical/RISK_AND_KILL_GATES.md` — GATE-002 and GATE-013 measurements, thresholds, fallbacks, and decision rules.
- `docs/canonical/GLOSSARY_AND_ID_REGISTRY.md` — RR-COORD-1, RR-FLOAT-1, RR-JCS-SHA256-1, terminology, and ID families.
- `docs/canonical/RESEARCH_LEDGER.md` — current Apple/ARKit evidence and the distinction between documented capability and measured suitability.

### Contract field and lifecycle authority
- `docs/contracts/README.md` — CON-001 through CON-005 invariants and compatibility policy.
- `docs/contracts/frame-packet.schema.json` — CON-001 FramePacket fields and RRFP-WIRE-1 metadata.
- `docs/contracts/rrcap-manifest.schema.json` — CON-002 capture inventory and authoritative replay ordering.
- `docs/contracts/scene-state.schema.json` — CON-003 stable identity and readiness.
- `docs/contracts/edit-artifacts.schema.json` — CON-004 typed artifacts and spatial encodings.
- `docs/contracts/transaction.schema.json` — CON-005 transaction lifecycle, confirmation, commit, restore, and reconciliation.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Five closed JSON Schemas already define the 1.0.0 field and lifecycle authority.
- Canonical test and gate documents already define fixture IDs, expected evidence, thresholds, and rejection classes.

### Established Patterns
- Inputs are closed and versioned, unknowns fail closed, stable prefixed IDs carry identity, and measured evidence never replaces a TARGET without a reproducible record.
- No product implementation exists yet; Phase 1 must not pre-create unrelated monorepo or provider structure.

### Integration Points
- The Mode A seed is the first native integration point for signing, permissions, ARKit tracking/planes, portrait gating, and minimal FramePacket capture.
- The language-neutral fixture corpus is the join point for later Swift, JavaScript, Python, web, gateway, and replay consumers.

</code_context>

<specifics>
## Specific Ideas

Keep the initial app visibly diagnostic rather than product-polished: a compact internal checklist should make physical gate state and evidence export obvious while keeping all edit/provider behavior out of Phase 1.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope.

</deferred>

---

*Phase: 01-contract-and-device-proof*
*Context gathered: 2026-07-16*
