# Phase 7: Separate Mode B0 Web Fallback - Research

**Researched:** 2026-07-18
**Domain:** Local provider-independent Next.js replay, verification, timeline, and inspection
**Confidence:** HIGH for repository and architecture; MEDIUM for current framework guidance; browser evidence not yet run

<user_constraints>
## User Constraints (from CONTEXT.md)

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

### Deferred Ideas (OUT OF SCOPE)
- General `.rrcap` upload/import and adversarial archive UI.
- MP4/MOV ordinary-video decode, timeline, codec support, and geometry-unavailable behavior.
- Session creation/listing, server TTL, deletion queue, audit log, share links, share invalidation, authentication, authorization, and cloud storage.
- Typed B0 proposals, explicit replay forks, gateway authority, live phone connectivity, WebSockets, and acknowledged-commit fault campaigns.
- Sparse plane/point/mesh/reveal/asset visualization beyond metadata for artifacts actually present in the selected verified fixture.
- Learned providers, dense geometry, LingBot/B1, GPU/runtime tiers, production deployment, and multi-user behavior.
- Full `GATE-008` two-run and browser/fault evidence, complete `FR-WEB-001`, and complete `SEC-RETENTION-001` acceptance.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Canonical acceptance | Sprint treatment |
|---|---|---|
| `FR-WEB-001` | Separate Next.js sessions/timeline, `.rrcap` and ordinary-video replay, sharing, typed proposals, sparse/artifact visualization, and explicit degradation. | Implement only the approved golden `.rrcap` verify/replay/scrub/inspect subset; leave the requirement pending. [VERIFIED: `.planning/REQUIREMENTS.md`; PRD FR-WEB-001; sprint cut] |
| `SEC-RETENTION-001` | Local-only default plus explicit server TTL, deletion, share invalidation, source/derived cleanup, and ID-only audit logs. | Enforce/display local-only fixture state and add no server persistence/share surface; leave the requirement pending. [VERIFIED: `.planning/REQUIREMENTS.md`; PRD SEC-RETENTION-001; sprint cut] |
| `GATE-008` | Two exact provider-disabled replays plus scene/artifact/transaction inspection, typed fixture edit, ordinary video, and camera/codec/quota/network degradation evidence. | Build and smoke only the minimal replay/inspection path; the full gate remains pending. [VERIFIED: `RISK_AND_KILL_GATES.md:113-122`; `.planning/milestones/v1.0/SPRINT-CUT-36H.md:51`] |
</phase_requirements>

## Summary

The repository already owns the hard part: an exact, fail-closed Node replay verifier for frozen `FX-CAPTURE-001`. It validates schemas, paths, inventory, self-hashes, packet/event bindings, global-journal order, projections, recovery rules, and expected digests, then publishes canonical reports atomically. Phase 7 should call that verifier from a Next.js server-only adapter, require the accepted `archive.finalized-one-frame` report, and only then read the verified archive into a minimal serializable view model. [VERIFIED: `tools/javascript/src/replay.ts`; Phase 2 summaries/tests]

The browser does not need an archive parser, gateway, API route, database, 3D renderer, or provider. A Server Component can load the verified DTO directly and pass it to one Client Component containing a controlled native range input. This follows the App Router boundary: Server Components are default; `server-only` prevents accidental client imports; Client Component props must be serializable. [CITED: https://github.com/vercel/next.js/blob/v16.2.9/docs/01-app/01-getting-started/05-server-and-client-components.mdx]

The smallest honest UI is therefore a replay status header, capability/degradation ledger, selected-frame preview, timeline scrubber, event detail, manifest/privacy detail, and explicit empty states for scene, transactions, and unavailable artifacts. No current fixture evidence supports a canonical transaction or spatial scene viewer. [VERIFIED: frozen one-frame archive manifest and event payload inventory]

**Primary recommendation:** implement `server-only exact verifier -> verified DTO -> single in-memory timeline client`, fail closed before DTO publication, and keep all full web/retention/gate claims pending.

## Architectural Responsibility Map

| Responsibility | Owner | Boundary |
|---|---|---|
| Exact capture verification/replay | Existing `runReplay` under exact Node `v22.22.3` | Sole authority for trusted/untrusted classification; do not duplicate. [VERIFIED: `replay.ts`] |
| Fixture and report orchestration | New `web/src/lib/replay/load-golden-capture.server.ts` (suggested) | `import 'server-only'`; repository-relative allowlisted paths only. [CITED: Next.js server/client docs] |
| Verified presentation DTO | Pure projection helper | Accepts only an accepted verifier report and verified fixture bytes; returns JSON-serializable values. [VERIFIED: project fail-closed boundary rule] |
| Page composition | App Router Server Component | Calls the server loader directly; no self-fetching route handler. [CITED: https://github.com/vercel/next.js/blob/v16.2.9/docs/01-app/02-guides/production-checklist.mdx] |
| Timeline interaction | Small `'use client'` component | Holds selected index only; cannot read files or verify content. [CITED: Next.js server/client docs] |
| Canonical mutations, sharing, sessions | Not present | Must remain visibly unavailable/deferred; no gateway authority exists in this slice. [VERIFIED: ADR-002, ADR-013, sprint cut] |

## Existing Code and Fixture Inventory

| Seam | Verified state | Planning consequence |
|---|---|---|
| `tools/javascript/package.json` | Exact Node `22.22.3`; AJV, formats, canonicalize only. [VERIFIED: repository package manifest] | Keep exact runtime. Import/reuse this package rather than copying verification logic. |
| `runReplay(options)` | Returns `void`, verifies all frozen archives/probes, and publishes exactly sixteen reports to a previously nonexistent output root. [VERIFIED: `replay.ts:636-719`] | Adapter must create an exclusive temporary parent, choose a nonexistent child output root, read the accepted report, and clean up in `finally`. |
| Publication behavior | Stages mode-0600 reports, fsyncs, renames atomically, and removes only failed staging. [VERIFIED: `replay.ts:646-687`] | Do not point it at a shared/persistent web directory or reuse an existing output path. |
| Replay tests | Prove complete corpus, byte identity, wrong-runtime rejection, and one-byte corruption failure without output publication. [VERIFIED: `tools/javascript/test/replay.test.mjs`] | Add adapter regressions; retain Phase 2 tests as the verifier oracle. |
| Golden accepted archive | One accepted frame, seven event records plus journal records, one synthetic PNG, local-only/not-shared manifest state. [VERIFIED: `finalized-one-frame.rrcap`] | Enough for verify/replay/scrub/frame and privacy inspection; not enough for real scene/transaction visualization. |
| Existing web surface | No Next app, web package, deployment config, or browser harness is tracked. [VERIFIED: repository file inventory] | Create one separate `web/` package; do not retrofit `tools/javascript` into a UI package. |

## Recommended Stack

Pin exact versions; do not use floating `latest` during the sprint.

| Package/runtime | Version | Why / evidence |
|---|---:|---|
| Node.js | `22.22.3` | Exact runtime required by the existing verifier and present locally. [VERIFIED: `EXACT_NODE_VERSION`; `node --version`] |
| `next` | `16.2.9` | Matches the Accepted ADR's inspected line and the queried official docs; MIT, Node `>=20.9.0`, published 2026-06-09. [VERIFIED: npm registry metadata; ADR-002] |
| `react`, `react-dom` | `19.2.7` | Mutually compatible exact pair; MIT, published 2026-06-01. [VERIFIED: npm registry metadata and peer dependency] |
| `typescript` | `6.0.2` | Stable, aged exact compiler pin; Apache-2.0, published 2026-03-23. Avoid the week-old 7.x line during the sprint. [VERIFIED: npm registry metadata] |
| `@types/node` | `22.19.7` | Exact major aligned with verifier runtime; MIT. [VERIFIED: npm registry metadata] |
| `@types/react`, `@types/react-dom` | `19.2.17`, `19.2.3` | Exact React 19 type pins; MIT. [VERIFIED: npm registry metadata] |

Package-name legitimacy checks found the official repositories, very high weekly use, no deprecation, and no postinstall scripts. The checker marked the unversioned current `next`, `typescript`, and `@types/node` names `SUS` only for recent latest-package publication; the selected Next 16.2.9 and TypeScript 6.0.2 pins predate that threshold and were independently verified through npm metadata. [VERIFIED: GSD package-legitimacy output and npm registry metadata]

## Package Legitimacy Audit

| Exact package | Verdict | Registry/repository evidence | Install decision |
|---|---|---|---|
| `next@16.2.9` | `OK (exact pin)` | MIT, official `vercel/next.js`, Node `>=20.9.0`, published 2026-06-09, no postinstall. The name-level checker warning referred to the newer latest release, not this pin. [VERIFIED: npm metadata] | Allowed. |
| `react@19.2.7` | `OK` | MIT, official `facebook/react`, published 2026-06-01, no postinstall. [VERIFIED: npm metadata and legitimacy check] | Allowed. |
| `react-dom@19.2.7` | `OK` | MIT, official `facebook/react`, exact peer `react ^19.2.7`, published 2026-06-01, no postinstall. [VERIFIED: npm metadata and legitimacy check] | Allowed. |
| `typescript@6.0.2` | `OK (exact pin)` | Apache-2.0, official `microsoft/TypeScript`, Node `>=14.17`, published 2026-03-23, no postinstall. The name-level checker warning referred to the newer latest release. [VERIFIED: npm metadata] | Allowed as development-only compiler. |
| `@types/node@22.19.7` | `OK (exact pin)` | MIT, official DefinitelyTyped repository, exact Node-22 line published 2026-01-15, no postinstall. The name-level checker warning referred to the newer latest major. [VERIFIED: npm metadata] | Allowed as development-only types. |
| `@types/react@19.2.17` | `OK` | MIT, official DefinitelyTyped repository, published 2026-06-05, no postinstall. [VERIFIED: npm metadata and legitimacy check] | Allowed as development-only types. |
| `@types/react-dom@19.2.3` | `OK` | MIT, official DefinitelyTyped repository, published 2025-11-12, no postinstall. [VERIFIED: npm metadata and legitimacy check] | Allowed as development-only types. |

Do not add Tailwind, shadcn, Three.js, Zustand, archive/upload packages, a database, Playwright, or cloud SDKs. Plain CSS, React state, Node filesystem/crypto/temp APIs, and the existing verifier cover this slice. [VERIFIED: approved scope; engineering inference]

## Recommended Project Shape

```text
web/
├── package.json                    # separate exact dependency lock
├── next.config.ts
├── tsconfig.json
└── src/
    ├── app/
    │   ├── globals.css
    │   ├── layout.tsx
    │   ├── page.tsx                # Server Component
    │   └── error.tsx               # explicit fail-closed UI boundary
    ├── components/
    │   └── replay-explorer.tsx     # only necessary Client Component
    └── lib/replay/
        ├── load-golden-capture.server.ts
        ├── project-verified-view.ts
        └── types.ts
```

Tests should stay next to the pure projection/client seams or in `web/test/`. Keep repository-root resolution in one server module; never derive an arbitrary path from URL/search/user input. [VERIFIED: untrusted-input boundary and sprint fixture decision]

## Data Flow and Fail-Closed Sequence

```text
allowlisted fixture manifest
        │
        ▼
exact Phase 2 runReplay (server only, temp output)
        │ accept report required
        ▼
read verified manifest/events/frame metadata + fixture image
        │ pure allowlisted projection
        ▼
serializable VerifiedReplayView
        │ Server Component prop
        ▼
Client timeline selection + inspection only
```

1. Resolve repository root and fixed fixture/report identifiers from constants, not request data. [VERIFIED: context decision]
2. Create a temporary directory with `mkdtemp`, reserve a nonexistent `reports` child, and call `runReplay` with exact runtime and a valid `git:<40hex>` implementation revision. [VERIFIED: replay options and output preconditions]
3. Read `archive.finalized-one-frame.replay-report.json`; require `verdict === 'accept'`, null rejection, expected fixture ID/revision/hash, and expected archive name before reading UI data. [VERIFIED: report test/oracle]
4. Read only manifest-declared, digest-bound paths needed for the view. Keep JSON values bounded and map identifiers/types explicitly. [VERIFIED: project boundary rules]
5. If any step fails, return/render a typed failure with no partial timeline. Always remove the temporary parent in `finally`. [VERIFIED: fail-closed sprint decision]
6. Pass primitives/arrays/plain objects to the Client Component. [CITED: Next.js serializable-props requirement]

Avoid invoking the complete replay verifier once per client interaction. The page needs one verified snapshot, then scrubbing is purely local. A process-local memoized promise is acceptable only if failures are not converted into success and the fixture/revision key is exact; no persistent cache is needed. [ASSUMED: implementation optimization]

## UI Contract

The minimum page should make these facts impossible to miss:

- Recorded replay, provider-independent, local fixture, gate pending.
- Verification verdict, fixture/archive IDs, manifest/report digest, accepted frame/event/journal counts, and finalization state.
- A native `<input type="range">` with keyboard-accessible event index, previous/next controls if useful, and exact selected event sequence/type/time/durable journal sequence.
- Frame preview only for the manifest-bound accepted frame; image alt text must say synthetic golden fixture where applicable.
- Privacy panel: capture state, local-only retention scope, share state, deletion state, and no browser persistence.
- Capability ledger: replay/timeline/frame metadata available; scene/transactions/sparse geometry/providers/share/typed proposals/ordinary video unavailable or not present.
- No button for unavailable behavior. Status text is safer than a disabled control that implies a backend exists.

A controlled range input is a standard React state pattern and preserves native keyboard behavior. [CITED: https://github.com/react/react/blob/main/packages/react-devtools-shared/src/devtools/views/SuspenseTab/SuspenseScrubber.js]

## Patterns to Use

### Server-only verifier adapter

```ts
import 'server-only'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { runReplay } from '../../../../tools/javascript/src/replay'

// Constants select the frozen fixture; no request-controlled path enters here.
// Verify first, project second, cleanup in finally.
```

`server-only` produces a build-time error if the module enters the client graph. [CITED: Next.js 16.2.9 server/client component documentation]

### Narrow client boundary

```tsx
'use client'

export function ReplayExplorer({ replay }: { replay: VerifiedReplayView }) {
  const [selected, setSelected] = useState(0)
  return <input type="range" min={0} max={replay.events.length - 1} value={selected}
    onChange={(event) => setSelected(Number(event.currentTarget.value))} />
}
```

Only the interactive leaf needs `'use client'`; the verifier, filesystem, and page data loading remain server-side. [CITED: Next.js 16.2.9 server/client component documentation]

## What Not to Hand-Roll

- Do not reimplement archive path safety, schema validation, JCS/SHA-256, manifest self-hash, frame/event records, global journal, recovered-prefix logic, or replay equality. Use `runReplay`. [VERIFIED: Phase 2 ownership]
- Do not turn the Next app into the production gateway or WebSocket authority. ADR-002 explicitly forbids that topology. [VERIFIED: ADR-002]
- Do not infer scene state or transactions from capture lifecycle events. Absence is a valid inspector result. [VERIFIED: fixture inventory]
- Do not infer ARKit pose/scale/planes/geometry from ordinary media or the synthetic preview image. [VERIFIED: ADR-013 and rrcap manifest contract]
- Do not create fake local share/delete/TTL behavior to satisfy retention copy. The server lifecycle remains pending. [VERIFIED: SEC-RETENTION-001]

## Common Pitfalls

1. **Verifier output reuse:** `runReplay` rejects an existing output root. Generate a new isolated output child and clean its parent. [VERIFIED: replay tests]
2. **Runtime drift:** Next 16 accepts many Node versions, but replay accepts only `v22.22.3`; enforce the repository runtime before page verification. [VERIFIED: exact replay guard]
3. **Client contamination:** Importing `replay.ts`, Node filesystem, or fixture paths from a Client Component can bundle/fail/leak boundaries. Mark the adapter `server-only`. [CITED: Next.js docs]
4. **Partial trust:** Do not parse/display events first and verify later. A rejection yields no trusted DTO. [VERIFIED: project fail-closed rule]
5. **Fixture overclaim:** The one-frame archive is synthetic and lacks edit transactions. UI prose must not imply a live room, learned output, or complete operation journey. [VERIFIED: fixture payloads]
6. **False gate closure:** A production build and one browser smoke are not the two-run/fault/ordinary-video/full-retention gate. Preserve pending IDs. [VERIFIED: sprint cut and GATE-008]
7. **Async component unit tests:** Official guidance says Vitest does not support async Server Components reliably; test pure adapters/components and use an actual end-to-end smoke for the async page. [CITED: https://github.com/vercel/next.js/blob/v16.2.9/docs/01-app/02-guides/testing/vitest.mdx]

## Verification Guidance for the Planner

Automated work can establish:

- existing Phase 2 replay tests remain green under exact Node;
- the adapter emits a DTO only after an accepted exact report;
- wrong runtime, corrupt fixture copy, missing report, wrong verdict/fixture ID, and unsafe/unexpected path fail closed with no partial timeline;
- event and frame ordering match manifest/global-journal values;
- scene/transaction absence and provider/share/ordinary-video unavailability copy cannot be promoted to available;
- timeline selection is bounded and keyboard-operable;
- `npm run build` succeeds with no Node-only module in the client bundle;
- one real local browser smoke proves load, labels, scrub, detail change, frame preview, and no network/provider call if a browser tool is actually available.

Do not mark `FR-WEB-001`, `SEC-RETENTION-001`, or `GATE-008` complete from these results. The sprint preflight wording should remain narrowly `minimal local golden-capture B0 replay/inspection path passed automated checks` plus a separate actual browser-smoke result if run. [VERIFIED: sprint honesty rule]

## Environment and Dependency Findings

- Local Node is `v22.22.3` and npm is `10.9.8`. [VERIFIED: command output]
- No `agent-browser` executable was found during research. Browser automation must be installed/available later or recorded pending; this research claims no browser run. [VERIFIED: environment probe]
- No product web dependencies are currently installed or tracked. [VERIFIED: repository inventory]
- Next.js 16.2.10 was published very recently; use 16.2.9 because it is the canonical ADR-inspected line and official Context7 source available for this research. [VERIFIED: npm metadata; ADR-002]

## Assumptions and Resolutions

| Question | Resolution |
|---|---|
| Can a fixed repository fixture satisfy the sprint's word `open`? | Yes for the explicitly reduced smoke slice; no for general import acceptance. The UI names it a local demo fixture. [VERIFIED: sprint cut/context] |
| Should verification happen in the browser? | No. Exact existing Node verification is safer and smaller; only verified presentation crosses the boundary. [VERIFIED: existing implementation plus Next boundary] |
| Is a route handler needed? | No. A Server Component can call the server adapter directly; a self-fetch adds another boundary with no client need. [CITED: Next production checklist] |
| Can the present fixture demonstrate scene/transaction inspection? | Only honest empty/absent inspector states. A richer fixture requires a new canonical, hash-bound revision and is not assumed. [VERIFIED: fixture inventory] |
| Is local browser persistence useful? | Not in this sprint. It creates quota/deletion/retention semantics that the slice does not implement. [VERIFIED: context decision] |
| Must the app deploy? | No. Local build and actual smoke are the authorized evidence; deployment/cloud/auth are out of scope. [VERIFIED: sprint scope] |

No unresolved product or technical question blocks planning.

## Sources

### Primary repository authority
- `AGENTS.md`; `docs/canonical/README.md`; `.planning/milestones/v1.0/SPRINT-CUT-36H.md`; `.planning/ROADMAP.md`; `.planning/REQUIREMENTS.md`. [VERIFIED]
- `docs/canonical/MASTER_TECHNICAL_SPEC.md`; `PRD.md`; `TEST_AND_EVALUATION_PLAN.md`; `RISK_AND_KILL_GATES.md`. [VERIFIED]
- ADR-001, ADR-002, ADR-004, ADR-008, ADR-011, ADR-012, ADR-013, ADR-014 and `docs/contracts/README.md`. [VERIFIED]
- `tools/javascript/src/replay.ts`, `tools/javascript/test/replay.test.mjs`, and `fixtures/capture/1.0.0/rev-001`. [VERIFIED]

### Current official/library evidence
- Next.js 16.2.9 Server and Client Components: https://github.com/vercel/next.js/blob/v16.2.9/docs/01-app/01-getting-started/05-server-and-client-components.mdx [CITED]
- Next.js production checklist: https://github.com/vercel/next.js/blob/v16.2.9/docs/01-app/02-guides/production-checklist.mdx [CITED]
- Next.js Vitest guidance: https://github.com/vercel/next.js/blob/v16.2.9/docs/01-app/02-guides/testing/vitest.mdx [CITED]
- React controlled scrubber reference: https://github.com/react/react/blob/main/packages/react-devtools-shared/src/devtools/views/SuspenseTab/SuspenseScrubber.js [CITED]
- npm registry metadata queried 2026-07-18 for every recommended exact package/version. [VERIFIED]

## Research Metadata

- Context7 documentation queries were cached under research-store keys `0f8a4f...098`, `31e04a...480`, and `f0db8b...ffc2` with `MEDIUM` provider confidence.
- Repository/canonical findings are `HIGH` confidence because they were read directly from tracked sources.
- Browser behavior is not measured in this research; no screenshot, browser support, load time, or gate evidence is claimed.

---

*Phase: 07-separate-mode-b0-web-fallback*
*Research completed: 2026-07-18*
*Ready for planning: yes*
