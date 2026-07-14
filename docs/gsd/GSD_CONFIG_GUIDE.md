# ReRoom GSD configuration guide

This guide explains the two reviewed configuration overlays prepared for GSD Core `1.6.1`. They are templates, not active configuration. Applying either template is prohibited until a later human has installed GSD, completed document ingestion without blockers, and allowed GSD to create `.planning/config.json`.

## Files and ownership

- `profiles/quality-fast.config.json`: default ReRoom delivery posture.
- `profiles/maximum-assurance.config.json`: elevated posture for architecture, security, irreversible data-contract, release, and kill-gate decisions.
- `../../scripts/apply_gsd_profile.py`: standard-library-only deep-merge utility.
- `.planning/config.json`: future GSD-owned active configuration; deliberately absent during this preparation.

The profiles contain only keys validated against the pinned central schema or released first-party capability registries. [GSD_CONFIG_KEY_MATRIX.md](GSD_CONFIG_KEY_MATRIX.md) provides a key-by-key audit trail.

## Profile choice

| Concern | `quality-fast` | `maximum-assurance` |
|---|---|---|
| Model fallback | Codex-aware `balanced` | Codex-aware `quality` |
| Per-phase model tiers | High for discuss/research/planning/verification; capable for execution/completion | High for all six phases |
| Overall granularity | `standard` | `fine` |
| Verification granularity | `standard` | `fine` |
| Parallel workflow | Enabled | Disabled |
| Human verification | End of phase | Mid-flight |
| Research before questions | No | Yes |
| Discussion passes | Up to 2 | Up to 3 |
| Code-review depth | Standard | Deep |
| Plan-review convergence | Release default | Explicitly enabled |
| Context guard | Warn | Auto-manage |
| Security threshold | ASVS 1; block high+ | ASVS 2; block medium+ |

Use `quality-fast` for normal phase discussion, planning, execution, and verification. Switch to `maximum-assurance` when a mistake would be expensive to reverse or when the canonical risk/kill-gate documentation requires elevated evidence. Switch back after that bounded work is complete; the assurance profile is intentionally slower and more expensive.

## Shared safety posture

Both profiles:

- remain interactive and disable automatic phase advance;
- enable research, plan checks, the verifier, Nyquist validation, gap analysis, bounded repair, code review, UI review/safety, context coverage, and security enforcement;
- ground plan review in repository evidence using the effective stable `grep` authority;
- enable context-warning hooks;
- keep worktrees disabled for the Codex runtime;
- use released phase-tier aliases and the runtime model catalog instead of guessed model IDs;
- keep execution granularity at `standard` so fine planning does not mechanically split implementation into incoherent fragments.

## Deliberate stable-version deviations

Some attractive settings appear in GSD prose but cannot be encoded safely in v1.6.1:

1. **No `gates.*` or `safety.*`.** The canonical key validator does not accept them. Human control is represented through `mode`, `auto_advance`, `human_verify_mode`, the verifier, and the specific UI/security/context capabilities.
2. **No parallel subkeys.** `parallelization.plan_level`, `task_level`, `skip_checkpoints`, `max_concurrent_agents`, and `min_plans_for_parallel` are not stable schema keys. A requested “max 3 task-level agents” therefore cannot be truthfully encoded. The profiles use only the supported top-level boolean.
3. **No object-form `parallelization.enabled`.** One loader path recognizes it, but canonical validation rejects it. Boolean form avoids a split-brain configuration.
4. **No Codex worktrees.** `workflow.use_worktrees` is false because the pinned implementation does not support the desired Codex path reliably.
5. **No claimed injection-blocking hook.** `security.injection_blocking` is schema-valid, but the pinned Codex installer does not install/register the read-injection scanner. External content must still be treated as untrusted evidence.
6. **No explicit model IDs.** `runtime: "codex"` plus stable `opus`/`sonnet` phase tiers and the fallback model profile let the pinned catalog resolve compatible Codex entries. These aliases are GSD quality tiers, not hard-coded Claude selections.
7. **No repository-wide forced TDD mode.** ReRoom spans native, web, backend, deterministic geometry, and AI evaluation; phase plans must select the canonical test method for each boundary.
8. **No `workflow.plan_chunked` default.** Stable chunked planning improves crash recovery for unusually large/hanging plans, but adds outline/per-plan task and commit overhead. Select it only for a phase whose size or Windows stdio behavior warrants it.
9. **No literal `firecrawl`, `brave_search`, or `exa_search` value.** GSD masks these values in UI but can persist plaintext in `.planning/config.json`. ReRoom uses a process environment/secret manager only.

## When the active config exists

After successful new-mode ingestion, inspect `.planning/`. The ingest workflow guarantees project artifacts but does not guarantee `.planning/config.json`. If config is missing, use the installed `$gsd-settings` skill once and allow GSD to materialize it. Do not create a hand-authored replacement and do not run `new-project` after ingestion.

From repository root, preview and interactively apply the normal profile with:

```text
python scripts/apply_gsd_profile.py quality-fast
```

The utility prints a sorted unified before/after diff. Type exactly `apply` to continue. It then creates a UTC timestamped sibling backup such as:

```text
.planning/config.json.backup-20260714T120000Z
```

and atomically replaces `.planning/config.json`. Any other response cancels without changing files. `--yes` is available for a separately reviewed non-interactive workflow, but interactive use is preferred:

```text
python scripts/apply_gsd_profile.py quality-fast --yes
```

To switch to the assurance profile:

```text
python scripts/apply_gsd_profile.py maximum-assurance
```

To return to normal delivery:

```text
python scripts/apply_gsd_profile.py quality-fast
```

The merge is recursive for objects, replaces arrays as whole values, preserves active keys not mentioned by the profile, and makes the selected profile authoritative for overlapping keys. It refuses missing files, malformed/non-object JSON, symlinks, unknown profile names, secret-like keys, and string-valued Firecrawl/Brave/Exa integration settings. Boolean/null provider-detection controls are not secrets and remain allowed. It never starts GSD.

## Codex agent materialization

GSD's installer writes static model/effort choices into project-local Codex agent TOML files. At the initial install, `.planning/config.json` does not yet exist, so those agents cannot reflect the later selected overlay. After ingestion, config materialization, and profile application, rerun the same pinned command if the selected model tier must be materialized:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

Then fully restart Codex. Do not substitute `latest`, and do not rely on the uncorroborated `codex --reload` suggestion.

## Verification after application

Before planning, verify all of the following without exposing environment values:

- `.planning/config.json` parses as one JSON object;
- `runtime` is `codex`;
- selected `model_profile`, all six `models.*` phase tiers, granularity, parallelization, human verification, code-review depth, context guard, and security levels match the chosen profile;
- `workflow.auto_advance` remains false;
- `workflow.use_worktrees` remains false;
- no unsupported keys from the deviations list appeared;
- the profile diff and backup path were recorded in the operator log;
- after any reinstall/restart, the expected GSD skills still appear in Codex's `$` skill picker.

Do not print Firecrawl or other secret values during verification.

## Rollback

The most recent timestamped backup is the immediate configuration rollback source. Review the diff, copy the selected backup over `.planning/config.json`, and then rerun the exact pinned installer plus a full Codex restart only if materialized agent settings also need to be restored. If GSD auto-committed generated planning, use a non-destructive `git revert <commit>` for repository rollback.

Never use `git reset --hard` or delete partially generated planning before preserving it for conflict diagnosis.
