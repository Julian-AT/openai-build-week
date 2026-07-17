# STATE Archive

Pruned entries from STATE.md. Recoverable but no longer loaded into agent context.

## Pruned 2026-07-18 (phases 1-1, kept recent 1)

### Decisions

- [Phase 01]: Gate automation is limited to UNRUN, RUNNING, and RED; GREEN and WAIVED_BY_HUMAN require a human actor and signed checklist digest.
- [Phase 01]: Checked-in gate evidence contains sanitized facts and opaque external artifact digests only; raw/private evidence remains outside Git.
- [Phase 01]: A waiver requires an explicit lock-change ID plus updated PRD and affected ADR digests before validation.
- [Phase 01]: Plan 01-04: All six dependency roots are approved only at their audited exact versions, artifact integrity or revision, licenses, and sources.
- [Phase 01]: Plan 01-04: Resolved transitives are allowed only as the exact compatible-license, integrity or pin-bound closure proven reachable from an approved root.
- [Phase 01]: Fixture and result acceptance requires bounded reads plus exact manifest, schema, case, artifact, summary, and digest agreement. — Fail closed on any oracle or normalized-result drift.
- [Phase 01]: Full automated preflight never consumes physical reports; gate alone requires bound signed GREEN GATE-013 and GATE-002 evidence. — Preserve the automation/human authority boundary and retain RED as non-success evidence.
- [Phase 01]: Plan 01-05: JavaScript parses untrusted fixture JSON with bounded duplicate-aware and Unicode-strict handling before validation or canonicalization.
- [Phase 01]: Plan 01-05: RRFP output remains the exact trailer-less 24-byte-header format, and RunnerResultV1 metadata is derived only from independently computed bytes.
- [Phase 01]: Plan 01-06: Python rejects duplicate JSON names and invalid Unicode before schema validation or RFC 8785 canonicalization.
- [Phase 01]: Plan 01-06: Python RRFP and coordinate results derive metadata only from computed bytes while expected artifacts remain read-only integrity oracles.
- [Phase 01]: Plan 01-07: Fresh parity requires actual JavaScript and Python outputs, exact expected runner identities, one shared Git revision, complete comparator agreement, and unchanged oracle hashes.
- [Phase 01]: Plan 01-07: Mutation gates operate only on temporary copies and must kill semantic, wire, path, completeness, digest, and fixture-integrity faults independently.
- [Phase 01]: Plan 01-08: Swift accepts only the exact 35-keyword frozen schema profile and rejects unknown, remote, or dynamic schema behavior before compilation. — Keep CON-001 through CON-005 closed and evidence-bound.
- [Phase 01]: Plan 01-08: swift-json-schema remains pinned at 0.13.1/f299eb1 with a bounded RFC 3339 date-time checker for reference parity. — Preserve the approved dependency while matching canonical whole-second timestamps.
- [Phase 01]: Plan 01-08: Public validation treats schema ID, version, and hash as untrusted strings and requires all five exact schema registrations. — Fail closed on schema-selection spoofing and tamper.
- [Phase 01]: Plan 01-08: Contract input limits may be lowered but never exceed 32 MiB or depth 64, and validation returns no coerced or defaulted document. — Keep later Swift consumers bounded and deterministic.
- [Phase 01]: Plan 01-09: Frozen checked-in bytes and stable rejection classes are the Swift serialization and coordinate policy authority. — Malformed input fails closed without repair or hidden defaults.
- [Phase 01]: Plan 01-09: RRFP remains exactly the 24-byte big-endian prefix, canonical header, and payload with no trailer. — Preserve CON-001 byte identity and reject any undeclared extension byte.
- [Phase 01]: Plan 01-09: RR-COORD-1 quantizes inputs through binary32 and preserves row-major serialization with column-vector math. — Match the immutable coordinate oracle and inclusive tolerance semantics.
- [Phase 01]: Plan 01-09: Archive paths require normalized ASCII relative segments plus symlink-aware root containment. — Prevent traversal, separator-confusable, absolute, and symlink escape attacks.
- [Phase 01]: Plan 01-10: Swift accepts only the exact immutable manifest digests for the three frozen fixture families. — Prevent an omitted or altered corpus from redefining its own oracle.
- [Phase 01]: Plan 01-10: Three-runtime evidence binds Swift, JavaScript, and Python to one exact implementation revision and source-tree digest. — Make agreement evidence attributable and reproducible while failing closed on source drift.
- [Phase 01]: Plan 01-10: Agreement reports publish atomically only after all fresh runtime results pass the closed comparator. — Prevent partial or mismatched evidence from being recorded as success.
- [Phase 01]: Plan 01-10: Durable reports retain raw-result digests rather than temporary raw output files. — Preserve exact reproducibility without retaining path-bearing ephemeral artifacts.
- [Phase 01]: Plan 01-11: iOS 26.0 remains only the ASSUMED Xcode 26.4/base-iPhone-17 Phase 1 proof baseline pending Plan 01-14 physical evidence. — Do not infer a broader product minimum OS or D-05 promotion from simulator success.
- [Phase 01]: Plan 01-11: Microphone readiness uses authorization only and never creates audio capture. — Keep optional microphone state independent from camera, ARKit, visual FramePacket, and typed/tap availability.
- [Phase 01]: Plan 01-11: Physical landscape changes capture eligibility only and never pauses or restarts AR tracking. — Preserve session continuity while coaching portrait capture.
- [Phase 01]: Plan 01-11: ARKit uses world tracking with horizontal and vertical planes only, with no scene reconstruction, scene depth, or rear-LiDAR gate. — Keep the base-iPhone path capability-driven and compatible with the locked no-LiDAR requirement.
- [Phase 01]: Plan 01-12: World-frame reset or relocalization always advances the sole epoch owner; only one finite rigid correction with matching directed base and target versions can release affected quarantine. — Prevent silent relabeling or heuristic alignment from making stale spatial data capture-eligible.
- [Phase 01]: Plan 01-12: CON-001 image and packet bytes become internally durable through one staging-directory rename, but remain non-visible and non-network-eligible until the exact CON-002 journal lifecycle is synced. — Keep file durability distinct from authoritative replay visibility and prevent partial capture publication.
- [Phase 01]: Plan 01-12: Simulator tests embed the existing frozen contract schema resources so full ContractValidator checks do not depend on inaccessible host-repository paths. — Validate the canonical schema bytes inside the simulator without copying or altering the canonical contracts.
- [Phase 01]: Plan 01-13: Automation evidence emits only UNRUN, RUNNING, or RED; GREEN and WAIVED_BY_HUMAN remain external signed human decisions. — Preserve deterministic gate authority and prevent exporter self-approval.
- [Phase 01]: Plan 01-13: Evidence is reconstructed from a closed allowlist, independently validated, and durably published only after validation. — Keep private raw evidence outside the report and fail closed before filesystem mutation.
- [Phase 01]: Plan 01-13: One app target selects its root at compile time, and Release excludes diagnostic and exporter source files entirely. — Prove shipping UI and binary absence rather than merely hiding controls at runtime.
- [Phase 01]: Plan 01-13: Release inspection resolves the same DerivedData app built by the shared scheme and never rebuilds or substitutes another product. — Bind the surface claim to the product exercised by Release XCUITest.
- [Phase 01]: Plan 01-15: Bind three-runtime evidence to the last source-changing revision a5bff6896188dcac9397c48ce1a6820a7196011a. — The declared source scope is byte-identical at closeout and excludes the publisher and generated reports, preserving a non-self-referential provenance chain.
- [Phase 01]: Plan 01-15: Advance deterministic compatibility evidence identities to _002 without changing fixtures or runtime policy. — The implementation binding changed, so the reports require a new evidence-run identity while frozen oracle and comparator meaning remain exact.
- [Phase 01]: Plan 01-15: Preserve the signed physical gate chain unchanged during host-only provenance repair. — Physical observations retain separate human authority and are verified only by protected byte comparisons in this plan.

### Performance Metrics

| 1 | 15 | - | - |
