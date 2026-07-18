# Phase 8: P0 Hardening and Evidence — Research

**Researched:** 2026-07-18
**Domain:** Final demo integration, evidence integrity, security/license audit, and submission readiness
**Confidence:** HIGH for repository/canonical state; MEDIUM for live submission-page details

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 — Fail-closed entry:** Phase 8 must first audit repository reality. It may consume Phase 5, 6, or 7 behavior only when the corresponding implementation summary and declared verifier exist and pass. Missing `05-04`, `06-03/04`, or `07-02/03` outputs remain explicit prerequisites; Phase 8 must not infer them from plans or partial source.
- **D-02 — One integration path:** Add no feature surface. The sprint hardening path composes existing phase verifiers, focused package/app/web checks, Release-surface inspection, and one representative demo rehearsal. It must not create another transaction, replay, contract, or gate authority.
- **D-03 — Honest run classification:** Automated simulator/local-HTTP results may be called `automated checks passed`. A signed-device result may be called `device-smoke verified` only after the real run is retained. Neither result closes `OPS-GOLDEN-001`, which remains `PENDING` until 5/5 consecutive runs occur after every blocking gate is green.
- **D-04 — Security and safety:** Run tracked-source, built-client, app-bundle, capture/evidence, and sanitized-log credential scans; rerun typed/tap and adversarial transaction coverage; inspect the shipped surface for unexpected model, provider, tool, upload, deployment, or deletion authority. The sprint uses no live provider credential and adds no external service.
- **D-05 — License freeze:** Generate an exact sprint bill of materials from checked-in lockfiles, Swift resolution, local assets, and fonts/resources. Add no dependency. The repository-owned proxy's missing root license/use-and-redistribution approval and any incomplete transitive evidence keep `OPS-LICENSE-001` and `GATE-011` pending; Phase 8 must report the gap rather than invent approval.
- **D-06 — Evidence and runbook:** Produce one sanitized evidence index, one operator demo runbook, and one machine-checkable pending-gate report. Every entry binds a stable ID, implementation revision, digest, command or procedure, evidence location, and actual state. Raw room media, private traces, credentials, signing material, machine paths, and user/device identifiers remain outside Git.
- **D-07 — Submission boundary:** Prepare, but do not publish or deploy, the project description/checklist/video shot list. The official rules currently require a working project, category/description, repository URL, a public YouTube demo under three minutes with audio explaining Codex/GPT-5.6 use, and a representative `/feedback` Codex Session ID. A human must perform the final rules recheck, choose the representative session, approve public media, and submit.
- **D-08 — Claims:** The strongest permitted sprint claim is: `ReRoom demo candidate: automated integration checks passed; representative device/browser smoke recorded where linked; deferred P0 gates remain pending.` Do not say `P0 complete`, `release ready`, `real-time`, `measured`, `licensed for shipping`, or any gate is green without its canonical evidence record.
- **D-09 — Change boundary:** No schema/ADR/product-meaning change, dependency install, cloud resource, deployment, publication, PBX/signing edit, provider integration, voice, B1, or broad refactor belongs in this phase.

### the agent's Discretion

- Exact names and closed shapes for the composite verifier, sprint BOM, evidence index, pending-gate report, and runbook.
- How to order existing quick checks so failures are cheap and diagnostics remain stable and sanitized.
- Whether repeated existing checks are invoked directly or through one thin repository-owned orchestrator, provided the original verifiers remain authoritative.
- Markdown layout and evidence cross-linking, provided every status is mechanically checkable and no raw/private evidence enters Git.

### Deferred Ideas (OUT OF SCOPE)

- Full physical `GATE-001`, compositor/performance `GATE-003`, reveal/vote `GATE-006`, B0 fault `GATE-008`, reconnect `GATE-009`, catalog/license/parity `GATE-011`, or runtime-tier `GATE-012` campaigns.
- General upload, accounts, sharing, TTL/deletion backend, ordinary-video import, live phone/web synchronization, cloud deployment, learned providers, voice, and B1.
- New observability infrastructure or performance instrumentation intended to manufacture missing historical measurements.
- Any product change made only to improve submission copy or video appearance.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Canonical requirement | Sprint research support |
|---|---|---|
| `NFR-LATENCY-001` | Record synchronized p50/p95/max stage distributions without unsupported real-time claims. | Do not create missing metrics in this slice. Index existing actual measurements, label absent stages `PENDING`, and retain local/no-provider fallback. [VERIFIED: `docs/canonical/PRD.md`; `SPRINT-CUT-36H.md`] |
| `NFR-RESILIENCE-001` | Preserve capture integrity, acknowledged edits, restore, and session isolation across tracking/network/worker faults. | Compose existing crash/idempotency/recovery tests; the full tracking/reconnect campaigns remain pending. [VERIFIED: `TEST_AND_EVALUATION_PLAN.md`; Phase 2/3/6 summaries] |
| `SEC-CREDENTIAL-001` | Keep standard credentials out of source, logs, captures, browser/app bundles, and clients. | Run repository, evidence, built web client, and Release-app scans; no live credential/bootstrap is needed by the local sprint slice. [VERIFIED: `PRD.md`; existing phase verifier source] |
| `SEC-AGENT-001` | Treat external/model text as untrusted; only typed allowlisted proposals may reach deterministic authorization. | Rerun the existing typed/tap, injection, target/session, fingerprint, confirmation, and authority regressions; do not add a model surface. [VERIFIED: `ADR-011`; Phase 3 summaries] |
| `OPS-LICENSE-001` | Bind every shipped library/asset/font/weight to exact source/version/digest, terms, attribution, and use/redistribution approval. | Produce a sprint BOM and blockers. The absent root license/explicit proxy redistribution decision prevents formal closure. [VERIFIED: `PRD.md`; `git ls-files`; Phase 3 proxy provenance] |
| `OPS-GOLDEN-001` | Complete 5/5 consecutive signed-device four-operation journeys plus matching B0 after blocking gates are green. | Prepare one representative rehearsal and exact operator procedure only; keep 5/5 pending. [VERIFIED: `TEST_AND_EVALUATION_PLAN.md`; sprint cut] |
| `OPS-SUBMISSION-001` | Deliver the working project, repository/setup/testing guidance, public sub-three-minute audio demo, Codex/GPT explanation, and representative Session ID with supported claims. | Prepare the checklist, evidence links, shot list, and human handoff; do not publish or submit autonomously. [CITED: https://openai.devpost.com/; https://openai.devpost.com/rules] |
</phase_requirements>

## Summary

Phase 8 should be planned as a two-plan consolidation slice, not the original canonical S8 release campaign. Plan A should add a thin fail-closed readiness/composite verifier and exact security/license inventory. Plan B should run the available integration checks, publish a sanitized evidence index and all-gate status report, and prepare the human demo/submission runbook. No plan should implement missing Phase 5–7 behavior. [VERIFIED: repository inventory; `.planning/SPRINT-CUT-36H.md`]

The decisive repository fact is that upstream work is incomplete: Phase 5 lacks `05-04-SUMMARY.md`, Phase 6 lacks `06-03/04` summaries, and Phase 7 lacks `07-02/03` summaries at research time. Therefore Phase 8 needs explicit prerequisite discovery with stable `BLOCKED_BY_UPSTREAM` outcomes rather than a verifier that silently skips missing surfaces. [VERIFIED: `.planning/phases/05-*` through `07-*`; repository file audit]

The checked-in gate truth is also narrower than the roadmap goal: `GATE-002` and `GATE-013` have formal `GREEN` reports, `GATE-001` is `RUNNING`, and the sprint register leaves the other full campaigns deferred/pending. A consolidated report must preserve the difference between a formal gate state and a sprint disposition; it must never invent `PENDING` as a canonical gate-record state. [VERIFIED: `evidence/device/phase-01/*.json`; `evidence/capture/phase-02/gate-001-report.json`; `RISK_AND_KILL_GATES.md`]

**Primary recommendation:** Build one fail-closed integration/evidence orchestrator over existing authorities, then produce a BOM, evidence index, pending-gate matrix, demo runbook, and submission checklist—without new product code, dependencies, or gate promotion.

## Architectural Responsibility Map

| Capability | Primary tier | Secondary tier | Rationale |
|---|---|---|---|
| Upstream readiness and composite checks | Repository orchestration | Existing phase verifiers | The composite owns ordering and status only; semantic verdicts remain with phase-specific tools. [VERIFIED: `scripts/verify-phase-*`] |
| Native four-operation smoke | Native app/XCTest/XCUITest | Swift package tests | Native branch authority and app UI already own transaction/render behavior. [VERIFIED: `ReRoomTransactionCore`; `ReRoomDeviceProofTests`] |
| B0 replay smoke | Next.js server/client | Existing Phase 2 Node replay runner | The web boundary projects only after the Phase 2 verifier accepts the fixed capture. [VERIFIED: `07-01-SUMMARY.md`] |
| Secret/safety audit | Repository and built artifacts | Existing injection/release tests | Source-only scanning is insufficient; browser/app bundles and evidence must also be checked. [VERIFIED: `TST-CREDENTIAL-001`; phase verifiers] |
| Shipping BOM | Evidence tooling | Lockfiles/resource manifests | Product code must not decide its own license approval. [VERIFIED: `OPS-LICENSE-001`] |
| Gate/evidence index | Evidence tooling | Human operator | Automation records facts and pending procedures; human/physical evidence remains human-authoritative. [VERIFIED: evidence schemas and sprint cut] |
| Public submission | Human operator | Prepared repository artifacts | Public upload, Session ID selection, rules sign-off, and submission are externally consequential actions. [VERIFIED: Context D-07] |

## Current Readiness Matrix

| Surface | Repository state at research | Phase 8 treatment |
|---|---|---|
| Phase 2 capture/replay | Seven summaries and passing automated preflight; formal `GATE-001` remains `RUNNING`. | Reuse quick/full verifier; index its report; do not rerun the deferred physical matrix automatically. [VERIFIED: Phase 2 summaries/evidence] |
| Phase 3 transaction core | Seven summaries and revision-bound automated preflight; formal GATE-009/010/011 campaigns pending. | Rerun quick transaction/injection/crash checks and reuse exact trace evidence. [VERIFIED: `03-07-SUMMARY.md`] |
| Phase 4 target/compositor fallback | Four summaries and automated fallback preflight; physical/provider/runtime gates pending. | Rerun quick fallback checks only; keep measured/device claims absent. [VERIFIED: `04-04-SUMMARY.md`] |
| Phase 5 replacement | Implementation through `05-03`; final evidence summary absent. | Require `05-04-SUMMARY.md` and verifier pass before integrated replacement evidence. [VERIFIED: Phase 5 directory] |
| Phase 6 removal | Reducer and durable authority through `06-02`; app/demo/evidence summaries absent. | Require `06-03/04` before demo integration; deterministic transaction tests alone do not show removal UI. [VERIFIED: Phase 6 directory] |
| Phase 7 B0 | Verified server DTO through `07-01`; page/evidence summaries absent. | Require `07-02/03` before HTTP/browser/demo integration. [VERIFIED: Phase 7 directory] |
| Submission | Official pages currently list July 21, 2026 8:00 PM EDT and a sub-three-minute public audio demo plus repository and Session ID. | Prepare checklist; human rechecks immediately before submission. [CITED: https://openai.devpost.com/; https://openai.devpost.com/rules] |

## Standard Stack

### Core

| Tool | Observed version | Use | Rule |
|---|---:|---|---|
| Bash | system `/bin/zsh`/portable script environment | Thin fail-fast orchestration | Call existing verifiers; do not reproduce their semantics. [VERIFIED: existing scripts] |
| Python | 3.13.12 | Independent closed evidence/BOM/status validation and mutation tests | Standard library first; reuse existing `tools.verify` conventions. [VERIFIED: environment probe; Phase 3/4 verifiers] |
| Node/npm | 22.22.3 / 10.9.8 | Exact web tests, typecheck, build, and local HTTP smoke | Use checked-in locks with scripts disabled during install. [VERIFIED: environment probe; `web/package.json`] |
| Swift/Xcode | Swift 6.3 / Xcode 26.4 | Package, XCTest/XCUITest, Debug/Release, release-surface checks | Keep Swift 6 actor/test patterns and existing project; no PBX edit. [VERIFIED: environment probe; `Package.swift`] |
| Git/JQ/SHA-256 | Git 2.50.1; system jq | Revision binding, tracked-file discovery, closed JSON inspection, byte digests | Never stage or clean unrelated dirt. [VERIFIED: environment probe; AGENTS.md] |

### Existing Product/Test Dependencies

Use the exact checked-in SwiftPM/npm/Python locks and the existing Phase 1 dependency audit. Do not update or install a new direct dependency in Phase 8. [VERIFIED: `Package.resolved`; both `package-lock.json` files; `requirements.lock`; dependency audit]

## Package Legitimacy Audit

Not applicable: the recommended Phase 8 slice adds no external package. The BOM must audit the already locked closure, including web transitives and local assets, but package legitimacy is not redefined by this phase. [VERIFIED: Context D-05/D-09]

## Recommended Architecture Patterns

### Pattern 1: Prerequisite-gated composition

The composite verifier should use three states per upstream surface: `READY`, `FAILED`, or `BLOCKED_BY_UPSTREAM`. `READY` requires both the expected implementation summary and executable verifier. A missing prerequisite is not a passing skip and should prevent only dependent checks/evidence publication. [VERIFIED: Context D-01]

```bash
# Planning pattern only; existing phase scripts remain authoritative.
require_artifact "06-04-SUMMARY.md" "scripts/verify-phase-06-removal"
run_named_check "phase06_quick" scripts/verify-phase-06-removal quick
```

### Pattern 2: Stage, independently validate, then atomically publish

Generate the BOM/index/status report in a private temporary directory, validate closed keys, source revision, digests, statuses, forbidden values, and cross-links independently, then replace the checked-in sanitized artifact only after every required automated check passes. Failed or blocked runs publish nothing. [VERIFIED: Phase 3/4/7 plan patterns]

### Pattern 3: Separate formal gate state from sprint disposition

Each gate row should contain `formal_record` (`GREEN`, `RUNNING`, `RED`, `UNRUN`, `WAIVED_BY_HUMAN`, or `NO_REPORT`) and a separate `sprint_disposition` (`retained_green`, `fallback_active`, `deferred_pending`, or `running`). This avoids writing the planning word `PENDING` into a canonical gate-state field. [VERIFIED: `RISK_AND_KILL_GATES.md`; sprint cut]

### Pattern 4: Evidence index, not evidence aggregation

Index sanitized tracked evidence by relative path, SHA-256, implementation revision, requirement/gate/test IDs, verifier, classification, and actual status. Do not concatenate raw logs, images, videos, ballots, machine paths, or private traces. External physical artifacts remain opaque IDs plus digests/retention facts. [VERIFIED: evidence templates; AGENTS.md]

### Suggested Two-Plan Split

1. **08-01 — Readiness, integration, safety, and BOM verifier:** prerequisite matrix, composite quick checks, credential/bundle/source scans, exact lock/resource inventory, mutation tests, stable failure classes.
2. **08-02 — Evidence index, pending-gate report, rehearsal/runbook, and submission handoff:** run the available full smoke, publish sanitized artifacts atomically, document one representative manual run without claiming 5/5, and prepare the human rules/video/Session-ID checklist.

## Don't Hand-Roll

| Problem | Do not build | Use instead | Reason |
|---|---|---|---|
| Contract/JCS/replay verification | A fourth parser or digest implementation | Phase 1–3 runners and frozen fixtures | Equal new output could be equally wrong; existing independent oracles are pinned. [VERIFIED: Phase 1–3 summaries] |
| Transaction/fault authority | A demo-only transaction runner | `NativeBranchAuthority`, Swift tests, and phase verifiers | A second path could bypass CAS/idempotency/restore invariants. [VERIFIED: ADR-012] |
| Gate promotion | A Boolean based on test success | Existing gate schemas plus human/physical procedures | Automated smoke cannot authorize physical/human gates. [VERIFIED: risk plan] |
| License approval | Inference from package-lock `license` strings | Exact BOM plus retained terms/source/use decision | Metadata alone does not establish asset/checkpoint redistribution approval. [VERIFIED: OPS-LICENSE-001] |
| Submission automation | Devpost/YouTube upload automation | Human checklist and prepared artifacts | Public publication and Session ID selection require human authority. [VERIFIED: Context D-07] |

## Common Pitfalls

1. **Silent upstream skip:** A composite command can look green while Phase 6/7 outputs are absent. Require explicit artifact/verifier presence and make blocked dependencies non-publishable. [VERIFIED: current repository inventory]
2. **Evidence freshness drift:** Existing reports are bound to older implementation commits. Index them as historical automated evidence; rerun source-bound verifiers after upstream completion instead of relabeling them current. [VERIFIED: evidence `implementation_revision` fields]
3. **Formal-state vocabulary drift:** `PENDING` is planning prose, not a canonical gate state. Preserve `NO_REPORT` plus deferred sprint disposition. [VERIFIED: risk plan]
4. **License closure by assertion:** The local proxy provenance says repository-owned, but no tracked root license exists. This remains a blocker until an explicit owner decision and distribution terms are recorded. [VERIFIED: proxy provenance; `git ls-files`]
5. **Bundle/source-only secret scan:** Credentials can leak into generated client/app products even when source is clean. Scan both tracked inputs and built outputs while excluding public identifiers and variable names. [VERIFIED: TST-CREDENTIAL-001]
6. **Simulator/browser terminology:** XCUITest, local HTTP, and HTML inspection are distinct from signed-device and real-browser smoke. Record each evidence class exactly. [VERIFIED: sprint honesty rule]
7. **Disk exhaustion:** Only about 1.2 GiB was free during research; full Xcode plus Next builds may fail before product assertions. Audit and remove only explicit rebuildable caches, then record the environment issue separately. [VERIFIED: environment probe; prior summaries]
8. **Submission-rule staleness:** Official rules can change. Recheck the official rules and challenge page immediately before human submission. [CITED: https://openai.devpost.com/rules]

## Environment Availability

| Dependency | Available | Observed version/state | Fallback |
|---|---|---|---|
| Node/npm | Yes | 22.22.3 / 10.9.8 | None needed. [VERIFIED: probe] |
| Python | Yes | 3.13.12 | None needed. [VERIFIED: probe] |
| Swift/Xcode | Yes | Swift 6.3 / Xcode 26.4 | Host/package checks can proceed independently from simulator UI smoke. [VERIFIED: probe] |
| Git/jq | Yes | Git 2.50.1 / system jq | Python stdlib JSON is available if jq is absent elsewhere. [VERIFIED: probe] |
| Free disk | Risk | About 1.2 GiB | Reclaim only named rebuildable caches before full builds; never broad-clean. [VERIFIED: probe; AGENTS.md] |
| Physical device/human operator | Not assumed during autonomous work | External | Prepare procedure and mark result pending until performed. [VERIFIED: user availability and sprint cut] |
| Live provider/cloud | Not required | Intentionally absent | Typed/local/replay fallback is the sprint path. [VERIFIED: sprint cut] |

## Validation Architecture

Skipped because `.planning/config.json` explicitly sets `workflow.nyquist_validation` to `false`. Phase plans should still use the existing mutation-tested verifier convention and the smallest focused checks per task. [VERIFIED: `.planning/config.json`]

## Security and Evidence Domain

GSD `security_enforcement` is explicitly `false`, but canonical `SEC-CREDENTIAL-001` and `SEC-AGENT-001` remain required Phase 8 scope and cannot be skipped. [VERIFIED: `.planning/config.json`; `.planning/REQUIREMENTS.md`]

Required sprint checks:

- typed/tap and malformed/injection regression with models/network disabled;
- unexpected tool, target/session, transform, confirmation, license-bypass, deploy/delete, and secret-extraction rejection;
- repository/evidence/capture scans for credential-shaped values and private paths;
- built browser client and Release app scan;
- closed evidence diagnostics that emit stable IDs/classes, not raw content;
- no B1/provider/cloud dependency in product manifests or plans. [VERIFIED: TST-AGENT-001, TST-INJECTION-001, TST-CREDENTIAL-001, GATE-014]

## Open Questions

All planning questions were resolved fail-closed in `08-CONTEXT.md`:

1. Missing Phase 5–7 outputs are prerequisites, not assumed completion.
2. One rehearsal does not satisfy 5/5 golden acceptance.
3. Existing deterministic tests do not close reconnect or full adversarial campaigns.
4. Missing root license/redistribution approval keeps shipping license acceptance pending.
5. Public upload, Session ID selection, rules approval, and submission stay human-owned.
6. Missing physical/human evidence remains pending with an exact resume procedure, not a fabricated automated failure or pass.

## Deferred Resume Order

1. Complete missing Phase 5–7 implementation/evidence plans.
2. Resume full Phase 2 `GATE-001` physical verification.
3. Run `GATE-003`, `GATE-006`, `GATE-008`, `GATE-009`, and `GATE-011` formal campaigns.
4. Benchmark `GATE-004`, `GATE-007`, and `GATE-012` only when replacing current fallbacks.
5. Close canonical latency/resilience/security/license evidence and run `OPS-GOLDEN-001` 5/5.
6. Perform milestone audit and signed release/submission evidence review before a P0 claim. [VERIFIED: sprint-cut resume order plus canonical S8 dependencies]

## Assumptions Log

No unverified assumption is used to authorize implementation or a claim. Live submission details are MEDIUM-confidence official-page retrievals and are explicitly rechecked by a human before submission.

## Sources

### Primary — HIGH confidence

- `AGENTS.md`, `.planning/SPRINT-CUT-36H.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, and `08-CONTEXT.md`.
- `docs/canonical/README.md`, `PRD.md`, `MASTER_TECHNICAL_SPEC.md`, `TEST_AND_EVALUATION_PLAN.md`, `RISK_AND_KILL_GATES.md`, `DEVELOPMENT_STRATEGY.md`, and `RESEARCH_LEDGER.md`.
- Completed Phase 2–7 summaries, remaining Phase 5–7 plans, actual source/package/lock/resource/evidence inventory, and formal gate reports.

### Secondary — MEDIUM confidence

- https://openai.devpost.com/ — current challenge fields, demo rules, and judging criteria, retrieved 2026-07-18.
- https://openai.devpost.com/rules — current governing deadline and required submission items, retrieved 2026-07-18.

## Metadata

**Confidence breakdown:**

- Repository readiness: HIGH — verified from current files, git-tracked artifacts, and summaries.
- Architecture and evidence boundary: HIGH — directly constrained by accepted ADRs, canonical gates, and existing verifier patterns.
- Security/license gap assessment: HIGH — canonical criteria and current tracked inventory agree; no root license is tracked.
- Submission checklist: MEDIUM — fetched from official live pages but must be rechecked before submission.

**Research date:** 2026-07-18
**Valid until:** 2026-07-19 for repository readiness; submission rules must be rechecked immediately before submission.
