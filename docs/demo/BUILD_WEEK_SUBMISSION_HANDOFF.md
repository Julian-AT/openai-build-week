# Build Week Submission Handoff

> ReRoom demo candidate: automated integration checks passed; representative device/browser smoke recorded where linked; deferred P0 gates remain pending.

This document prepares a human-owned handoff. It does not authorize publication, repository visibility changes, Session ID disclosure, rules acceptance, or final submission.

## Official pages

- Official challenge: https://openai.devpost.com/
- Official rules: https://openai.devpost.com/rules
- Retrieved: 2026-07-18
- Deadline observed: July 21, 2026 at 5:00 PM Pacific Time.

Human must recheck both official pages immediately before submission. The live pages, eligibility, required fields, deadline, and repository-access rules control if they differ from this handoff.

## Current observed requirements

- A working project created using Codex with GPT-5.6.
- One category and a project description explaining what was created and how it works.
- A public YouTube demo under three minutes with audio explaining how Codex and GPT-5.6 were used.
- A repository URL with setup instructions, sample data if needed, testing guidance, key decisions, and where Codex accelerated the work.
- Repository access must follow the current official choice: public with relevant licensing, or private with the judge access specified on the challenge page.
- One representative `/feedback` Codex Session ID from the session where the majority of core functionality was built.

## Suggested entry package

- Category candidate for human confirmation: Apps for your life.
- Description focus: a native iPhone room-edit demo with deterministic `place`, `replace`, `remove`, and compensating `restore`, plus separate provider-independent local Mode B0 replay/inspection.
- Evidence links: `evidence/hardening/phase-08/evidence-index.json`, `evidence/hardening/phase-08/pending-gates.json`, and this repository's phase summaries.
- State blockers: OPS-GOLDEN-001 remains PENDING until 5/5. Device/browser/license/submission remain pending or blocked.

Normal signed-device removal remains unavailable; `remove` is only a bounded DEBUG demo fixture enabled by `--room-edit-demo-reveal`, and `GATE-006` remains PENDING.

Do not assert formal completion, shipping license approval, performance measurements, novelty comparisons, or green gates beyond the canonical reports linked in the evidence index.

## Video shot list — target under 2:45

1. `0:00–0:15` — Problem and controlled target: one chair or small table with visible floor.
2. `0:15–0:35` — Explain how Codex and GPT-5.6 supported architecture, contract-first implementation, and verification.
3. `0:35–1:35` — Signed DEBUG native sequence: `place`, `replace`, bounded fixture `remove`, `restore`; keep the `DEMO REVEAL FIXTURE - GATE-006 PENDING` banner visible and describe the limitation aloud.
4. `1:35–2:05` — Separate Mode B0 verified replay, timeline scrub, and inspection.
5. `2:05–2:25` — Deterministic/offline fallback and evidence boundary.
6. `2:25–2:45` — State the permitted demo-candidate claim and explicitly mention deferred gates.

Public media must exclude raw room/private imagery not approved for publication, credentials, signing/account details, machine paths, device/user identifiers, private traces, and unrelated notifications.

## Human-owned checklist

- [ ] Human: recheck and sign off official rules
- [ ] Human: confirm eligibility and category
- [ ] Human: approve project description and supported claims
- [ ] Human: approve public media
- [ ] Human: upload public demo video
- [ ] Human: confirm video is public, under three minutes, and has audible Codex/GPT-5.6 explanation
- [ ] Human: set repository visibility or judge access
- [ ] Human: confirm repository setup/testing guidance and relevant license state
- [ ] Human: choose representative /feedback Session ID
- [ ] Human: approve disclosure of that Session ID
- [ ] Human: enter repository, video, description, category, and Session ID in Devpost
- [ ] Human: submit final Devpost entry

## Final verification before the human submits

```bash
scripts/verify-phase-08-hardening --verify-evidence
scripts/verify-phase-08-evidence --verify-evidence
python3 tools/verify/verify_phase_08_evidence.py --docs docs/demo/PHASE_08_DEMO_RUNBOOK.md docs/demo/BUILD_WEEK_SUBMISSION_HANDOFF.md --index evidence/hardening/phase-08/evidence-index.json --gates evidence/hardening/phase-08/pending-gates.json
```

Any failed command stops the handoff. No automated command performs an upload or submission.

## Deferred Resume Order

1. Phase 5–7 automated implementation/evidence plans are complete; rerun their authoritative verifiers after any source change.
2. Resume `$gsd-verify-work 2` for the full `GATE-001` signed-device termination matrix.
3. Run formal `GATE-003`, `GATE-006`, `GATE-008`, `GATE-009`, and `GATE-011` campaigns against the frozen implementation.
4. Benchmark `GATE-004`, `GATE-007`, and `GATE-012` only if replacing the activated manual/no-dense/local fallbacks.
5. Complete the canonical latency/resilience distributions and security/license closure, then run `OPS-GOLDEN-001` 5/5.
6. Audit the milestone and assemble signed release/submission evidence before making a full P0 claim.
