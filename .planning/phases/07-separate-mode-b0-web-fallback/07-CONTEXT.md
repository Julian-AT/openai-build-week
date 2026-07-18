# Phase 7: Separate Mode B0 Web Fallback - Context

**Gathered:** 2026-07-18
**Status:** Sprint scope locked
**Mode:** Autonomous sprint cut

<decisions>
## Locked Decisions

- **D-01 — Product slice:** Deliver one separate, fixed-golden-capture recorded B0 replay with persistent provider-independent/local-fixture/GATE-pending copy and honest absent scene/transaction inspection.
- **D-02 — Verification and data flow:** Reuse the exact Phase 2 Node replay before projecting any serializable client DTO; fail closed with no partial trusted data.
- **D-03 — Scope and degradation:** Keep this sprint local and memory-only with upload, sessions, sharing, auth, cloud, ordinary video, typed forks, providers, and deployment unavailable/deferred.
- **D-04 — Evidence:** Automate the small slice but claim browser smoke only after a real browser run, keep the full matrix deferred, and leave FR-WEB-001, SEC-RETENTION-001, and GATE-008 pending.
- **D-05 — Agent discretion:** Choose the smallest plain Next/React/CSS structure, DTO, cleanup, and test seams that preserve every locked boundary without speculative dependencies.

### Product slice
- Build the smallest separate Next.js Mode B0 experience over one immutable, hash-bound repository golden `.rrcap`; it verifies, replays, scrubs, and inspects the recorded capture with every learned provider disabled.
- This sprint slice is a recorded fallback/debugging experience, not Mode A in a browser. Persistently label it `MODE B0 — RECORDED REPLAY`, `PROVIDER-INDEPENDENT`, `LOCAL DEMO FIXTURE`, and `GATE-008 PENDING` or equivalently unambiguous copy.
- The current golden one-frame capture contains capture/session/frame events but no canonical scene or transaction records. Inspectors must say `not present in this capture`; they must not invent scene, transaction, geometry, or provider output.

### Verification and data flow
- Reuse the existing exact Node `runReplay` verifier from `tools/javascript/src/replay.ts` on the server. Do not implement a second browser verifier or duplicate RR-JCS, path, inventory, digest, recovery, or replay rules.
- A server-only adapter may expose a small serializable verified-view DTO only after the exact verifier accepts. The interactive client owns only timeline selection/scrubbing and presentation; it does not authorize or reinterpret canonical state.
- Missing, corrupt, unsupported, or unverifiable fixture data fails closed: show the explicit failure and expose no trusted timeline or inspector data.
- Keep the fixture immutable and local. Browser state is in memory only; add no upload, filesystem picker, `localStorage`, IndexedDB, service worker, database, or server session store in this sprint.

### Scope and honest degradation
- Do not add deployment, cloud storage, gateway, WebSocket, authentication, account, sharing, deletion queue, ordinary-video import, typed proposal/fork, learned provider, or live-phone dependency.
- Render share, typed proposal, ordinary-video, and provider capabilities only as clearly unavailable/deferred status when useful; do not add inert controls that imply implementation.
- Local-only is the enforced default. Display the manifest's retention/share/delete state and explain that closing the tab discards browser UI state; do not claim the full `SEC-RETENTION-001` server lifecycle.
- `FR-WEB-001`, `SEC-RETENTION-001`, and `GATE-008` remain `PENDING`. The sprint may claim only that the minimal local golden-capture B0 replay/inspection path was implemented and smoke-tested where actual evidence exists.

### Evidence
- Automate the server adapter fail-closed behavior, verified DTO projection, timeline ordering/selection, capability copy, and production build. Add only the smallest test dependencies justified by those checks.
- A browser smoke claim requires an actual browser run against the built app. If browser automation is unavailable, record it as pending; never fabricate screenshots, browser coverage, fault-matrix results, or a gate pass.
- The full two-run browser replay, corrupt/missing degradation matrix, camera/codec/quota/network faults, ordinary-video behavior, acknowledged-commit preservation, sharing/deletion/TTL lifecycle, and supported-browser matrix remain deferred gate evidence.

### Agent Discretion
- Choose the exact `web/` file layout, component names, CSS, verified-view DTO shape, temporary-report cleanup strategy, and test runner while preserving the boundaries above.
- Prefer plain React/Next.js/CSS and Node built-ins. Avoid UI kits, 3D engines, archive libraries, state stores, persistence libraries, and production infrastructure unless a later measured need authorizes them.

</decisions>

<resolved_questions>
## Resolved Open Questions

1. **Does the sprint implement general upload?** No. It opens one repository-owned fixture through a server-only adapter; general archive upload and untrusted archive handling remain deferred.
2. **Does a verified replay require rewriting verification for the browser?** No. The app reuses the exact Phase 2 Node verifier before projecting a view DTO.
3. **Can the web client claim scene or transaction inspection on the current fixture?** It can expose those inspector sections, but their honest value is `not present in this capture` until a new hash-bound fixture contains such records.
4. **Where does replay data persist?** The fixture stays in the repository and the UI selection stays in memory. No browser or server persistence is added.
5. **Are sharing, typed edits, ordinary video, deployment, or auth required now?** No. They are explicitly deferred by the approved 36-hour sprint cut.
6. **Does this phase close `FR-WEB-001`, `SEC-RETENTION-001`, or `GATE-008`?** No. It provides the minimal local B0 smoke path and leaves the canonical requirements and evidence gate pending.
7. **What happens if exact verification fails?** The app fails closed with an explicit error and no trusted timeline/inspector payload.

</resolved_questions>

<code_context>
## Existing Code Insights

- `tools/javascript/src/replay.ts` exports `runReplay`, requires exact Node `v22.22.3`, verifies the complete frozen `FX-CAPTURE-001` corpus, and atomically publishes sixteen canonical replay reports to a new output directory.
- `tools/javascript/test/replay.test.mjs` already proves complete report publication, byte-identical repeat runs, exact runtime rejection, and one-byte corruption failure without publication.
- `fixtures/capture/1.0.0/rev-001/archives/finalized-one-frame.rrcap` is the smallest accepted golden archive: one accepted frame, seven event payload files, one image, and a manifest/global-journal binding.
- No Next.js application or web package currently exists. The repository has only the exact Node replay package under `tools/javascript`, so Phase 7 should add a separate `web/` package and import the replay source through an explicit server-only boundary.

</code_context>

<deferred>
## Deferred Register

- General `.rrcap` upload/import and adversarial archive UI.
- MP4/MOV ordinary-video decode, timeline, codec support, and geometry-unavailable behavior.
- Session creation/listing, server TTL, deletion queue, audit log, share links, share invalidation, authentication, authorization, and cloud storage.
- Typed B0 proposals, explicit replay forks, gateway authority, live phone connectivity, WebSockets, and acknowledged-commit fault campaigns.
- Sparse plane/point/mesh/reveal/asset visualization beyond metadata for artifacts actually present in the selected verified fixture.
- Learned providers, dense geometry, LingBot/B1, GPU/runtime tiers, production deployment, and multi-user behavior.
- Full `GATE-008` two-run and browser/fault evidence, complete `FR-WEB-001`, and complete `SEC-RETENTION-001` acceptance.

</deferred>

---

*Phase: 07-separate-mode-b0-web-fallback*
*Context gathered: 2026-07-18*
