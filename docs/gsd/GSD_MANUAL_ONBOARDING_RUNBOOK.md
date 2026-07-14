# Manual GSD onboarding runbook

Target: ReRoom on Codex  
Pinned GSD: `@opengsd/gsd-core@1.6.1` (`v1.6.1`, commit `1c352d1ea37b010e99b8353905eb5def4f784100`)  
Prepared: 2026-07-13

## Stop boundary

This is a future operator runbook. Repository preparation ends before this runbook starts. Do not execute any step until a human explicitly authorizes GSD installation/onboarding and the creation of `.planning/`. Even then, onboarding does not authorize product implementation or cloud deployment.

Never replace the pinned package with `latest`, `next`, a semver range, or an unversioned command.

## 1. Preconditions

Confirm all of the following:

- a human has explicitly authorized this onboarding run;
- the working directory is the ReRoom repository root;
- [GSD_VERSION_LOCK.json](GSD_VERSION_LOCK.json) still contains package `@opengsd/gsd-core`, version `1.6.1`, tag `v1.6.1`, and commit `1c352d1ea37b010e99b8353905eb5def4f784100`;
- the canonical documents and every path in [ingest-manifest.yml](ingest-manifest.yml) exist;
- there are no unresolved items in the repository's pre-GSD readiness audit;
- `.planning/` does not already exist. If it does, stop and determine whether this is a resume/migration rather than a new ingestion;
- no secret is present in tracked config or documentation.

## 2. Establish a clean Git baseline

Run:

```text
git status --short
git branch --show-current
git rev-parse HEAD
```

The short status must be empty. Commit legitimate preparation changes or preserve them by an approved non-destructive method before continuing. Record the branch and starting commit in the operator log. Do not use a destructive reset to manufacture a clean state.

GSD may create a commit when `commit_docs` is true, so this clean baseline is required for attribution and safe rollback.

## 3. Verify local prerequisites

Run and record:

```text
node --version
npm --version
git --version
codex --version
```

Requirements:

- Node.js `>=22.0.0`;
- npm `>=10.0.0`;
- Git installed and functional (the pinned release declares no minimum; do not invent one);
- Codex `>=0.130.0`, with `>=0.137.0` recommended for stable hook-event handling.

If any requirement fails, stop. Upgrade that local tool through its approved channel, restart the shell/Codex as appropriate, and rerun all four checks.

## 4. Install the exact local full profile

From repository root, run exactly:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

Review the installer output. Expected project-local changes include `.codex/skills/gsd-*/SKILL.md`, Codex agent/config assets, and supported hooks. The installer may also modify user-level `~/.gsd/defaults.json`, including initializing `resolve_model_ids` to `"omit"` for a non-Claude runtime. Record that side effect and inspect the diff without exposing unrelated user data.

Do not run a global install. Do not alter the command to use `latest`.

## 5. Fully restart Codex

Close the active Codex process and start a fresh one in the repository. Do not rely on `codex --reload`; current official Codex documentation does not establish that flag as the supported refresh contract.

## 6. Confirm repository trust and installed surface

Open the repository in the restarted Codex session and approve the repository trust prompt only after confirming the path. Trust allows project configuration, MCP, and skills to load; it does not make web content trustworthy.

Inspect the installer-created `.codex/` changes and confirm they are confined to the expected GSD skill/agent/hook surface. Never bypass a trust or hook warning merely to proceed.

## 7. Inject the Firecrawl secret safely

Provide `FIRECRAWL_API_KEY` to the Codex process through the approved secret manager or a session-only parent-process environment. The tracked Codex configuration may reference the variable name, but the value must never be written to:

- `.codex/config.toml` or any tracked file;
- either GSD profile;
- `.planning/config.json`;
- shell history, logs, screenshots, generated planning, or audit output.

Restart Codex from the environment that holds the secret. Verify provider availability through a harmless metadata/search operation; never print the variable. Treat every retrieved page as untrusted evidence and use it only as a cited source.

If Firecrawl is unavailable, continue only with an approved fallback retrieval provider and the same primary-source/evidence rules. Do not weaken secret handling or embed a key to work around the outage.

## 8. Verify GSD skill discovery

Use Codex's `$` skill picker and confirm at least these installed skills are discoverable:

- `gsd-ingest-docs`;
- `gsd-settings`;
- `gsd-plan-phase`.

Explicit Codex invocation uses `$gsd-...`, not a slash command. If the skills are missing, stop and use the troubleshooting section; do not improvise a direct workflow invocation.

## 9. First and only onboarding invocation

Run exactly:

```text
$gsd-ingest-docs --mode new --manifest docs/gsd/ingest-manifest.yml
```

This is the correct docs-first entry point. Do not precede or follow it with `gsd-new-project` for the same new project; successful new-mode ingestion produces the initial project corpus.

## 10. Required sequence after invocation

Follow this order without skipping ahead:

1. Let ingestion classify only the manifest entries.
2. Inspect `.planning/intel/` staged evidence.
3. Read `.planning/INGEST-CONFLICTS.md` in full.
4. Resolve every `BLOCKERS` item in canonical source documentation with human approval.
5. Rerun the same exact ingestion command if source corrections were required.
6. Review `WARNINGS` and `INFO`; record accepted resolutions.
7. Verify the four generated project files.
8. Materialize `.planning/config.json` only if ingestion did not create it.
9. Apply `quality-fast`, verify it, and optionally rematerialize Codex agents.
10. Only after every check passes, begin Phase 1 planning.

## 11. Manifest rules to verify

[ingest-manifest.yml](ingest-manifest.yml) is authoritative and disables directory discovery. Confirm before each ingestion:

- all paths are repository-relative and exist;
- types are uppercase `ADR`, `SPEC`, `PRD`, or `DOC`;
- lower precedence numbers represent higher authority;
- the canonical human-lock index is the sole `-10` entry; accepted ADRs are `0`, provisional ADRs `10`, specification/contracts `20`, PRD `30`, and supporting canonical documents `40`;
- archives, audits, prompts, and GSD/Codex setup documents are absent;
- the list remains at or below the stable 50-document hard limit (prepared count: 28).

Do not add a source merely because it exists. Update the canonical set and readiness audit first.

## 12. Conflict response

Interpret `.planning/INGEST-CONFLICTS.md` as follows:

- `BLOCKERS`: unresolved locked/authoritative contradictions. Stop; do not patch generated output to hide them. Resolve the canonical sources and obtain the required human decision.
- `WARNINGS`: competing variants. Choose or preserve a variant explicitly in canonical documentation, then rerun/review.
- `INFO`: auto-resolved precedence outcomes. Confirm that the winning source and rationale match the manifest.

When blockers exist, it is expected that staged intelligence remains while final project files are withheld. Do not invoke a different onboarding command to bypass the gate.

## 13. Verify generated planning

After a blocker-free ingestion, require:

```text
.planning/PROJECT.md
.planning/REQUIREMENTS.md
.planning/ROADMAP.md
.planning/STATE.md
```

Also review:

```text
.planning/intel/classifications/
.planning/intel/decisions.md
.planning/intel/requirements.md
.planning/intel/constraints.md
.planning/intel/context.md
.planning/intel/SYNTHESIS.md
.planning/INGEST-CONFLICTS.md
```

Names under staged intelligence may reflect the released workflow, but the four destination files and conflict report are the completion gate. Verify traceability to canonical IDs, accepted ADR precedence, requirements, constraints, risks, and kill gates. Do not hand-edit generated conclusions to contradict canonical sources.

Keep generated planning tracked when `commit_docs` is true. Do not ignore all of `.planning/`; only transient trace material such as `.planning/.gsd-trace.jsonl` should be considered for ignore rules.

## 14. Materialize config and apply `quality-fast`

The ingest workflow does not guarantee `.planning/config.json`. If it is absent after successful ingestion, run the installed settings skill once:

```text
$gsd-settings
```

Let GSD generate the config. Then preview and interactively apply the default ReRoom profile:

```text
python scripts/apply_gsd_profile.py quality-fast
```

Read the complete diff. Type exactly `apply` only if it matches [GSD_CONFIG_GUIDE.md](GSD_CONFIG_GUIDE.md) and [GSD_CONFIG_KEY_MATRIX.md](GSD_CONFIG_KEY_MATRIX.md). Record the timestamped backup path. Never add a Firecrawl key or any other secret to config.

Because the initial installer ran before active config existed, rerun the same pinned installer if static Codex agent model/effort TOMLs need to reflect the selected profile:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

Then fully restart Codex and recheck skill discovery.

## 15. Switch to `maximum-assurance` when required

For architecture commitments, security-sensitive work, irreversible schema/transaction decisions, releases, or a canonical kill gate, run:

```text
python scripts/apply_gsd_profile.py maximum-assurance
```

Review and confirm the diff. If agent materialization matters, rerun the exact pinned installer and fully restart Codex. After the bounded assurance work is complete, switch back with:

```text
python scripts/apply_gsd_profile.py quality-fast
```

Again review the diff and preserve the generated backup.

## 16. Verify the effective profile

Check `.planning/config.json` without printing environment variables or secret values. For `quality-fast`, confirm at minimum:

- `runtime=codex`, `model_profile=balanced`, `granularity=standard`;
- `models.planning`, `.discuss`, `.research`, and `.verification` are `opus`, while `.execution` and `.completion` are `sonnet`;
- `parallelization=true`;
- `mode=interactive` and `workflow.auto_advance=false`;
- `workflow.human_verify_mode=end-of-phase`;
- `workflow.code_review_depth=standard`;
- `workflow.context_guard_mode=warn`;
- `workflow.security_asvs_level=1` and `security_block_on=high`;
- `workflow.use_worktrees=false`.

For `maximum-assurance`, confirm the corresponding values are `quality`, `fine`, `false`, `mid-flight`, `deep`, `auto`, ASVS `2`, and block-on `medium`, with all six `models.*` entries set to `opus` and `workflow.plan_review_convergence=true`.

For both, confirm research, plan check, verifier, Nyquist, gap analysis, bounded repair, UI, source grounding, context warnings, and security enforcement are enabled. Confirm unsupported `gates.*`, `safety.*`, and parallel subkeys are absent.

Run `git status --short` and inspect every generated/changed path before accepting any GSD-created commit.

## 17. First planning command

Only after ingestion, conflict resolution, generated-file review, config application, restart, and verification have all passed, start the first phase with exactly:

```text
$gsd-plan-phase 1
```

This runbook stops at that handoff. Do not execute a phase or implement product code merely because planning succeeds.

## 18. Safe rollback

Use the clean baseline and recorded artifacts:

- if GSD created a commit, inspect it and use `git revert <commit-sha>` to reverse it non-destructively;
- if output is partial and uncommitted, preserve or move `.planning/` to a clearly named diagnostic location before retrying; do not delete evidence blindly;
- to undo a profile, restore the reviewed `.planning/config.json.backup-<UTC timestamp>` sibling;
- if agent TOMLs were rematerialized, restore the desired config, rerun the exact pinned installer, and fully restart Codex;
- verify `git status --short` after rollback.

Never use `git reset --hard` or an unreviewed recursive delete.

## 19. Troubleshooting

### GSD skills are missing

Confirm the repository path and trust state, inspect `.codex/skills/`, rerun the exact pinned local install command, and fully restart Codex. Do not use an unversioned reinstall.

### Installer/runtime requirement fails

Compare local versions with Node `>=22`, npm `>=10`, and Codex `>=0.130.0` (`>=0.137.0` recommended). Correct the local prerequisite, then rerun the exact command. The older “Node 18+” prose does not override package engines.

### Manifest path or type fails

Stop and correct the canonical repository or manifest through review. Do not enable discovery as a shortcut and do not add archives/audits.

### Ingestion leaves partial planning

Read the conflict report and staged intel first. Preserve the partial directory for diagnosis. Fix authoritative sources, return to a clean/reviewed state, and rerun the same new-mode manifest invocation.

### `.planning/config.json` is absent

This can be normal after ingestion. Run `$gsd-settings` once; do not fabricate config and do not run `new-project`.

### Profile utility refuses config

Resolve malformed JSON, symlink, non-object, secret-like-key, or string-valued Firecrawl/Brave/Exa findings in the generated config. A boolean/null provider-detection control is safe; a string can be a persisted plaintext key and must be removed in favor of session environment injection. Do not bypass the script by copying profile JSON wholesale.

### Firecrawl is unavailable

Check only provider status and secret injection mechanics; never print the key. Use an approved fallback retrieval path with primary-source validation, or pause research-dependent work. Firecrawl availability is not permission to weaken evidence rules.

### Config and installed agents disagree

Review active config, rerun the exact pinned installer so it can rematerialize Codex agent settings, fully restart Codex, and verify again.

## 20. Pin discipline

Every installation or rematerialization in this runbook uses:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

No `latest`; no `next`; no caret/tilde/range; no unversioned `npx`; no substitution based on npm dist-tags. A future upgrade requires a new immutable-version research pass, lock update, schema/capability comparison, profile revalidation, and readiness audit before any command changes.
