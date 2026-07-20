# Autonomous Hackathon Finish Plan — 2026-07-20

Status: **owner-authorized implementation overlay; canonical gates remain
evidence-driven**

## Objective

Turn the current demo candidate into one coherent, fast-to-run hackathon
workspace without weakening any deterministic ReRoom invariant. This overlay is
authorized directly by the owner and does not retroactively rewrite completed
phase plans or close physical, provider, and human gates.

## Locked boundaries

- Mode A remains native SwiftUI/ARKit and the live camera remains the
  photoreal background.
- P0 remains exactly `place`, `replace`, `remove`, and `restore`.
- AI and voice may produce typed, context-bound previews only. They cannot own
  identity, geometry, revision, persistence, confirmation, commit, or restore.
- One Hono API on Bun is the public application boundary. The Python/PyTorch
  service is private and reachable only through a bounded typed adapter.
- The official OpenAI JavaScript package is removed in favor of Vercel AI SDK
  provider adapters. Provider absence must preserve the deterministic demo.
- Large checkpoints are fetched only after license review, exact version and
  digest capture, adequate disk headroom, and a tested mock/fallback path.

## Delivery sequence

1. **Workspace and runtime.** Move JavaScript surfaces into a Bun/Turborepo
   workspace, retain package-local dependency ownership, preserve Swift as an
   Xcode/SwiftPM application, update paths, and prove the moved code still
   passes.
2. **API and AI boundary.** Replace the Node HTTP server and OpenAI package with
   Hono on Bun plus an internal `@reroom/ai` package using Vercel AI SDK. Preserve
   strict CON-006 validation, auth, rate limits, bounded bodies, redacted logs,
   and no-provider behavior.
3. **Private inference service.** Add a typed Python service with health,
   readiness, segmentation, depth, and reconstruction boundaries; implement
   deterministic fixture adapters first, then optional PyTorch/MPS providers.
   The Hono API owns all public routing and fails closed on worker timeout or
   invalid output.
4. **Voice preview tools.** Amend the AI boundary explicitly for a closed set of
   preview-only tools. Every result re-enters the same native proposal and
   deterministic preview boundary; confirmation remains a separate user action.
5. **Native cleanup.** Normalize product/module naming, split oversized SwiftUI
   presentation and state responsibilities along existing typed boundaries, and
   retain actor isolation, cancellation, accessibility, and deterministic tests.
6. **Engineering gates.** Add repository hooks and GitHub checks for frozen Bun
   installs, formatting/lint/typecheck/tests/builds, Swift tests, Python tests,
   secret scanning, and lockfile policy. No hook is the sole security boundary.
7. **Demo readiness.** Rewrite setup/architecture documentation, publish exact
   fallback order, run the smallest complete software gate, and leave every
   unmeasured device/provider/human claim visibly pending.

## Commit and verification policy

Commit each coherent slice after fresh relevant tests. Historical
revision-bound evidence is never silently regenerated: a new publisher revision
must bind the new workspace paths before it can replace old evidence. Any failed
provisional model or device gate activates the documented fallback rather than
changing P0.
