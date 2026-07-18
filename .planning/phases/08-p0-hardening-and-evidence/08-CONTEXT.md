# Phase 8: P0 Hardening and Evidence — Context

**Mode:** Autonomous 36-hour demo sprint cut
**Delivery classification:** Demo candidate, not a fully gated P0 release
**Discussed:** 2026-07-18

## Scope

Phase 8 is the smallest final integration, audit, demo-rehearsal, and submission-evidence slice for the approved sprint. It must make the implemented native four-operation journey and local Mode B0 replay easy to verify and demonstrate, but it cannot replace missing upstream implementation, physical-device measurements, human votes, or full canonical fault campaigns.

## Decisions

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

## Repository Readiness at Discussion Time

- Phases 2–4 have completed automated implementation/preflight summaries. `GATE-002` and `GATE-013` have checked-in `GREEN` reports; `GATE-001` is checked in as `RUNNING`.
- Phase 5 has implementation through `05-03`; `05-04-SUMMARY.md` is absent.
- Phase 6 has reducer/authority implementation through `06-02`; `06-03-SUMMARY.md` and `06-04-SUMMARY.md` are absent.
- Phase 7 has the verified server replay boundary through `07-01`; `07-02-SUMMARY.md` and `07-03-SUMMARY.md` are absent.
- The machine has the required Node/npm/Python/Swift/Xcode runtimes, but only about 1.2 GiB free disk was observed. Phase execution must reclaim only explicitly identified rebuildable caches before large Xcode/Next builds and must never clean user or repository data broadly.

## Open Questions Resolved

1. **Can Phase 8 start by assuming the Phase 6 demo and Phase 7 page work?** No. Its first check is an upstream artifact/verifier readiness audit; missing prerequisites stop only dependent integration checks and remain in the report.
2. **Can one representative sprint journey complete `OPS-GOLDEN-001`?** No. It is demo rehearsal evidence only; canonical acceptance remains 5/5 after blocking gates are green.
3. **Can existing deterministic tests close `GATE-009` or `GATE-010`?** No. They support the sprint smoke, while the complete reconnect and adversarial campaigns remain pending.
4. **Can the generated local proxy be declared shipping-approved?** No. Provenance exists, but the repository has no tracked root license and no complete redistribution decision. The BOM records this as a blocker for formal `OPS-LICENSE-001`/`GATE-011` closure.
5. **Should the agent submit or publish the demo?** No. It prepares the checklist, shot list, and evidence links. Public upload, repository visibility, Session ID selection, rules sign-off, and submission are human actions.
6. **Should missing physical/human evidence be converted to a failed automated check?** No. The automated surface verifies that the item is truthfully `PENDING`/unrun and points to its exact resume procedure.

## Deferred Ideas (OUT OF SCOPE)

- Full physical `GATE-001`, compositor/performance `GATE-003`, reveal/vote `GATE-006`, B0 fault `GATE-008`, reconnect `GATE-009`, catalog/license/parity `GATE-011`, or runtime-tier `GATE-012` campaigns.
- General upload, accounts, sharing, TTL/deletion backend, ordinary-video import, live phone/web synchronization, cloud deployment, learned providers, voice, and B1.
- New observability infrastructure or performance instrumentation intended to manufacture missing historical measurements.
- Any product change made only to improve submission copy or video appearance.

## Deferred Resume Order

1. Finish the missing Phase 5–7 implementation/evidence plans and rerun their authoritative verifiers.
2. Resume `$gsd-verify-work 2` for the full `GATE-001` signed-device termination matrix.
3. Run formal `GATE-003`, `GATE-006`, `GATE-008`, `GATE-009`, and `GATE-011` campaigns against the frozen implementation.
4. Benchmark `GATE-004`, `GATE-007`, and `GATE-012` only if replacing the activated manual/no-dense/local fallbacks.
5. Complete the canonical latency/resilience distributions and security/license closure, then run `OPS-GOLDEN-001` 5/5.
6. Audit the milestone and assemble signed release/submission evidence before making a full P0 claim.
