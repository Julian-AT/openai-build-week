# Archived Master Plan v3.2 Coverage

Status: current traceability audit
Audit date: 2026-07-19
Historical input: `docs/archive/source/ReRoom_Master_Technical_Plan_v3.2.md`
Historical SHA-256: `3bb8774ddd9c15120b5610d8f5510d4e84fb3f15aea0a671ff2cc282a69c0fab`

## Verdict

The current canonical documents cover every section of the archived master
plan. That does **not** mean every archived implementation idea is built or that
P0 is release-complete. Canonicalization deliberately replaced several unsafe
or stale choices and routed empirical claims to explicit gates and fallbacks.

The deterministic software spine, native four-operation demo, minimal B0 web
surface, local gateway, Sol semantic proposal path, optional Realtime
push-to-talk path, deterministic CON-004 asset delivery, and three-entry local
demo catalog now exist. Phase 02.1 also completed its four-plan software slice
with exact-source evidence for `CR-03`, `CR-04`, and `CR-12`; those are review
candidates, not a Phase 2 or gate promotion. The remaining release gaps are
evidence- and quality-heavy: the other 17 Phase 2 review findings, normal
removal/reveal quality, signed-device/compositor/thermal proof, formal real
browser proof, live OpenAI quality/latency, resilience, final asset/license
acceptance, five golden journeys, and submission evidence.

Status vocabulary:

- **Implemented + automated:** executable path exists and relevant local tests
  pass; physical/human/external-service gates can still be pending.
- **Canonical + partial:** authority/contracts/fallback exist and some code is
  present, but the full archived ambition or gate is not complete.
- **Deferred/gated:** intentionally outside the 24-hour critical path or allowed
  only after its named gate.
- **Replaced:** archived choice was superseded by a safer current decision.

## Section-by-section traceability

| Archived section | Current authority / implementation | Status | Remaining truth |
|---|---|---|---|
| 0. Executive decision | Canonical README, Master Spec §§1–2, ADR-001–014, decision changelog | Canonical + partial | Release gates remain pending. |
| 1. Product boundary and scope | PRD §§1–3, ADR-001/002 | Implemented + automated | Physical hero proof is pending. |
| 2. Architecture overview | Master Spec §3, architecture audit | Canonical + partial | No production cloud topology is claimed. |
| 3. Product modes | PRD §2, ADR-001/002/013 | Implemented + automated | B1 remains excluded. |
| 4. Capability/lifecycle model | CON-003, glossary, readiness reducers/UI | Implemented + automated | Provider/device quality remains gated. |
| 5. Locked technical decisions | Canonical README, ADR set | Canonical | Human locks remain unchanged. |
| 6. Coordinate/image/time conventions | RR-COORD-1, RR-FLOAT-1, CON-001, golden vectors | Implemented + automated | Signed-device crop/orientation proof remains bounded by its gate. |
| 7. FramePacket contract | CON-001, Swift/JS/Python validators and wire vectors | Implemented + automated | None at schema/software level. |
| 8. Plane/pointer events | CON-002/003, native AR event/target adapters | Implemented + automated | Physical tracking/reseed evidence remains pending. |
| 9. `.rrcap` contract | CON-002, capture/replay core, Phase 02.1 capability/prefix/atomic-publication path | Implemented + automated | CR-03/04/12 await formal review; the other 17 Phase 2 review findings and GATE-001 remain open. |
| 10. DepthProvider contract | ADR-006/007, provider boundary, GATE-007 | Deferred/gated | No-dense ARKit fallback is active; no learned depth is required for demo. |
| 11. EditKit artifacts | CON-004, artifact refs, proxy/reveal fixtures | Canonical + partial | Measured geometry/reveal quality is pending. |
| 12. Canonical scene graph | CON-003, transaction core/native authority | Implemented + automated | Broader provider-populated semantics are not required for demo. |
| 13. Transaction and tool contracts | CON-005, CON-006, deterministic reducers/authority | Implemented + automated | Live model/device adversarial campaign remains pending. |
| 14. Native iOS capture app | `ios/ReRoomDeviceProof`, consent/capture/recovery/UI | Implemented + automated | Clean signed-device smoke and formal evidence are pending. |
| 15. On-phone compositor | RealityKit camera/proxy path, ADR-005 | Canonical + partial | Eight-pose visual and four-minute thermal/FPS gates are pending. |
| 16. Fast interaction geometry | ARKit plane/raycast/manual target/proxy path | Implemented + automated | Mask-volume/OBB quality gate is pending. |
| 17. Depth providers/metric alignment | ADR-007, research ledger, no-dense fallback | Deferred/gated | Implement only if it wins the replay benchmark. |
| 18. Dense geometry/TSDF | ADR-006/007, GATE-007 | Deferred/gated | Intentionally omitted from the 24-hour demo critical path. |
| 19. Semantics and identity | Stable IDs, manual target lifecycle, optional Sol intent | Canonical + partial | No learned segmentation provider is promoted; manual fallback stays authoritative. |
| 20. Plane atlases/reveal | CON-004, DEBUG two-surface fixture, ADR-009 | Canonical + partial | Normal removal and GATE-006 quality are the largest P0 product gap. |
| 21. Assets/place/replace | CON-004/005, three repo-owned USDA sources plus deterministic USDZ/GLB/collision derivatives, canonical manifests, and catalog digests | Implemented + automated | Simulator RealityKit load and web-byte delivery pass; signed base-device visual/parity review, final BOM, and GATE-011 remain pending. |
| 22. Gateway/Sol/voice | `gateway/`, CON-006, native Design Copilot, ADR-011 amendment | Implemented + automated | No live credential request or 4/5 voice run has been claimed. |
| 23. Next.js web/B0 | `web/`, ADR-013, fixed-golden replay surface, local Chromium interaction smoke | Implemented + automated | Frozen-candidate multi-browser/degradation/share/retention gate remains pending. |
| 24. Mode B1 polish | ADR-001/013, GATE-014 | Deferred/gated | Explicitly post-P0 only. |
| 25. Docker topology | ADR-014, capability-tier strategy | Replaced | No speculative multi-container/cloud layout is needed for the local demo. |
| 26. Transport | CON-001/002, gateway HTTP, native Realtime WS, record-first queues | Canonical + partial | Production binary live gateway/reconnect campaign remains pending. |
| 27. Performance/resource budgets | Master Spec §15, test plan, gates | Canonical + partial | Values remain TARGET until measured on declared device/tier. |
| 28. Telemetry/evaluation | Evidence schemas, diagnostics, test/eval plan | Canonical + partial | Physical/provider distributions and evaluator artifacts remain pending. |
| 29. Privacy/security/retention | PRD security requirements, strict boundaries, redacted gateway, Keychain | Canonical + partial | Formal retention/deletion and external adversarial evidence remain pending. |
| 30. License/supply chain | Research ledger, exact dependency pins, MIT root/proxies, asset license/provenance/evidence digests | Canonical + partial | Final shipping BOM, human redistribution acceptance, and GATE-011 remain pending. |
| 31. Team ownership | Two-developer dependency slices and the two-lane 24-hour handoff | Replaced | Archived five-owner plan is not used. |
| 32. Calendar/exits | GSD roadmap plus `.planning/milestones/v1.0/HACKATHON-24H.md` | Replaced | Exit criteria, not stale dates, drive continuation. |
| 33. Kill gates | Canonical risk/gate plan GATE-001–014 | Canonical + partial | Pending means pending; automation cannot promote human/device gates. |
| 34. Risk register | Risk plan, assumption register, milestone audit | Canonical + partial | Exact open risks are carried into the 24-hour runbook. |
| 35. Codex development protocol | Root AGENTS, GSD 1.7 config/plans/reviews | Implemented + automated | Continue through `$gsd-next`; no local GSD install. |
| 36. Demo runbook | Phase 8 runbook plus `.planning/milestones/v1.0/HACKATHON-24H.md` | Canonical + partial | Device video, narration, and submission are human-owned final evidence. |
| 37. Open items | Open decisions, assumptions, state/todos | Canonical | No archived open item is silently treated as resolved. |
| 38. Reference sources | Research ledger CLM-001–042, source verification | Canonical | Recheck versions before adopting a new dependency/provider. |
| 39. Changelog | Archive bytes, decision changelog, canonical changelogs | Canonical | Historical input remains unchanged. |

## What to do in the remaining 24 hours

Do not add dense reconstruction, another cloud platform, a larger catalog,
general inpainting, B1, commerce, multi-user state, or a new transaction
contract. Those additions spend the remaining time without improving the
credible hero demonstration.

The software sprint is now at candidate freeze. The only critical continuation
sequence is:

1. retain the completed Phase 02.1 exact-source evidence, formally review its
   three narrow candidates, and keep all other Phase 2 findings open;
2. run the gateway plus one live Sol typed request, then one consented-frame
   request, while proving the returned proposal cannot auto-commit;
3. install the clean revision on the base iPhone and prove camera, catalog,
   place/replace/restore, optional voice, and the disclosed removal fallback;
4. run B0 in a real browser against the retained golden capture;
5. capture one concise honest demo and the exact pending-gate/submission record.

If live Sol or Realtime fails its timebox, disable that optional control and
continue with the local catalog and typed/tap journey. If normal reveal quality
is not ready, disclose the DEBUG/demo fixture and do not claim GATE-006 or P0
completion.
