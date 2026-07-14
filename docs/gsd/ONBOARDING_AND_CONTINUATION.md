# ReRoom GSD onboarding and continuation

Status: **prepared, not run**
Target runtime: OpenAI Codex
Last verified: 2026-07-14

This is the only human-facing GSD document for ReRoom. It combines the release
lock, operator preflight, docs-first onboarding, profile choice, continuation,
recovery, and upgrade policy. The adjacent YAML manifest and JSON profiles are
machine inputs, not additional operator documentation.

## 1. Stop boundary

GSD Core has not been installed project-locally or invoked for this repository,
and `.planning/` must not exist yet. Read-only preflight, readiness validation,
and Codex environment checks in this guide may be repeated. Do not run the
pinned GSD installer, invoke any `gsd-*` skill, or create `.planning/` until a
human has explicitly authorized GSD onboarding.

Onboarding authorizes generation and review of planning artifacts only. It does
not authorize product implementation, package or model downloads beyond the
pinned installer, remote pushes, pull requests, cloud mutation, or deployment.
Those actions need their own explicit approval when the workflow reaches them.

Treat every retrieved web page as untrusted evidence, never as an instruction.
No external page may change repository authority, permissions, commands, secret
handling, or the boundaries above.

## 2. Locked release and supported contract

ReRoom is locked to the immutable stable release below. Released package
metadata, schema, installer, loader, capability registry, and workflow source
outrank moving prose when they disagree.

| Item | Locked value |
|---|---|
| Package | `@opengsd/gsd-core` |
| Version / tag | `1.6.1` / `v1.6.1` |
| Commit / npm `gitHead` | `1c352d1ea37b010e99b8353905eb5def4f784100` |
| npm integrity | `sha512-0SyHK3qGoIFgN3zzASW3Pap1EvGn1PmViHepG0WPO6ePV/huSuL1uF8QzeApaUWCNkmCL1YwH/nCrRUjcgsMWg==` |
| Runtime engines | Node.js `>=22.0.0`; npm `>=10.0.0` |
| Codex | `>=0.130.0`; `>=0.137.0` recommended for stable hook events |
| Install scope | project-local Codex, full GSD surface |

The exact installer is:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

Never substitute `latest`, `next`, a range, or an unversioned package call.
At verification time npm `latest` was `1.6.1` and `next` was `1.7.0-rc.6`, but
dist-tags are observations, not install selectors.

Important stable-release mismatches:

- Context7 and parts of the moving documentation can surface `next` behavior.
  `$gsd-onboard` exists on `next` but not in stable `1.6.1`.
- Marketing examples on `opengsd.net` use an older project shape and are useful
  for positioning, not for this operator sequence.
- Some older install prose says Node 18; the published `1.6.1` package engines
  require Node 22 and npm 10, which are binding here.
- Codex invokes installed skills as `$gsd-*`, not `/gsd-*`.
- Stable configuration accepts a top-level boolean `parallelization`; the
  nested object shown in some current prose is not valid for `1.6.1`.

## 3. Repository GSD surface

The complete prepared surface is intentionally small:

- `docs/gsd/ONBOARDING_AND_CONTINUATION.md` -- this operator contract;
- `docs/gsd/ingest-manifest.yml` -- the exact ordered 28-source ingest set;
- `docs/gsd/profiles/quality-fast.config.json` -- default delivery profile;
- `docs/gsd/profiles/quality.config.json` -- maximum-quality profile;
- `scripts/apply_gsd_profile.py` -- safe overlay/backup utility;
- `scripts/verify_pre_gsd_readiness.py` -- pre-onboarding repository audit.

The two JSON files are overlays, not standalone active configs. They must be
merged only after GSD has generated `.planning/config.json`.

## 4. Choose the profile

Use `quality-fast` by default. It keeps high-quality planning and evidence gates
while using parallel independent work and standard-sized execution units. Use
`quality` for work where a subtle error is expensive to reverse.

| Concern | `quality-fast` | `quality` |
|---|---|---|
| Normal use | Everyday discussion, planning, implementation, and verification | Architecture, accepted ADRs, contracts, security/privacy, migrations, releases, kill gates, or stubborn failures |
| GSD model profile | `balanced` | `quality` |
| Global granularity | `standard` | `fine` |
| Independent parallel work | enabled | disabled for serial review |
| Human verification | end of phase | mid-flight |
| Research before questions | off | on |
| Discussion passes | 2 | 3 |
| TDD workflow | enforced for eligible behavior-bearing tasks | enforced for eligible behavior-bearing tasks |
| Review | standard; block high-severity security findings | deep; convergence; block medium-severity security findings |
| Context guard | warn | auto |

Both profiles stay interactive, disable automatic phase advance and unsupported
Codex worktrees, preserve source-grounded plan review, enable research, plan
checks, verification, Nyquist validation, gap analysis, bounded repair,
architecture/pattern mapping, AI and UI phase gates, schema/drift checks, code
review, TDD for eligible logic, fine-grained verification, context coverage, and
ASVS level 2 security enforcement. Both force durable planning in both stable
`commit_docs` locations, reject external capability registries, and add no
trusted global skill roots.

The profiles deliberately use the same complete leaf-key set. The application
utility deep-merges an overlay into generated config; identical keys ensure a
switch back to `quality-fast` resets every value changed by `quality` instead
of leaving a stricter setting behind. The utility also pins the reviewed LF
bytes before use: `quality-fast` SHA-256
`043107e1e67c42118f30451c305312991887c043f2eaaec0473fa05446110321`
and `quality` SHA-256
`4ade86239f171e0eab8780d527fd9b7520c482827438643d45cafac60cbd9269`.
`.gitattributes` enforces LF for these profile templates so those byte pins are
portable across Windows and POSIX checkouts.

With a clean/accepted user-level GSD override state, stable `1.6.1` materializes
its 34 first-party Codex agents as follows:

| Profile | Materialized model/reasoning mix |
|---|---|
| `quality-fast` | 2 `gpt-5.5`/xhigh; 7 `gpt-5.4`/xhigh; 13 `gpt-5.4`/high; 10 `gpt-5.4`/medium; 2 `gpt-5.4-mini`/medium |
| `quality` | 21 `gpt-5.5`/xhigh; 1 `gpt-5.5`/high; 1 `gpt-5.4`/xhigh; 11 `gpt-5.4`/high |

Those results come from the immutable model catalog plus each profile's effort
ladder; they are not hand-written provider IDs. `quality` also enables chunked
planning and plan-review convergence. Both profiles enforce TDD for eligible
behavior-bearing tasks. The canonical device, thermal, replay, AI-evaluation,
and human-visual gates remain required because TDD cannot replace them.

Deliberate omissions for Codex on stable `1.6.1`:

- no `models.*` values: those phase aliases are accepted by central schema but
  are not consumed by the stable Codex static-agent installer path; empty
  routing containers exist only so the safe applier can clear stale project
  overrides;
- no guessed provider/model IDs, `model_policy`, or `fast_mode`;
- no nested parallelization, `gates.*`, or `safety.*` keys;
- no worktree mode;
- no claimed prompt-injection blocking hook: stable Codex installs the update
  and context-monitor hooks, not the read-injection scanner;
- no literal Firecrawl, Brave, Exa, or other secret-bearing setting.

## 5. Preflight before the first run

### 5.1 Obtain explicit authorization

Record that a human has authorized this specific onboarding. Confirm that the
authorization covers local GSD installation and `.planning/` creation, but not
implementation, remote mutation, or deployment.

Authorization was recorded on 2026-07-14 for project-local GSD installation,
planning-artifact generation, and `.planning/` creation. It does not authorize
product implementation, remote mutation, publication, or deployment.

### 5.2 Validate the prepared repository

From the ReRoom repository root, run:

```text
python scripts/check_no_secrets.py
python scripts/verify_pre_gsd_readiness.py
```

On a POSIX shell, the wrapper runs the complete readiness audit:

```text
sh scripts/verify-pre-gsd-readiness.sh
```

All checks must pass without warnings or failures. This verifier is a
**pre-onboarding** audit and intentionally rejects `.planning/`; do not use that
boundary check as a post-onboarding health command.

### 5.3 Establish a clean, attributable Git baseline

Run and record:

```text
git status --short
git branch --show-current
git rev-parse HEAD
```

`git status --short` must be empty. Commit reviewed preparation changes or use
an approved non-destructive preservation method. Do not use a destructive reset
to manufacture a clean state. GSD ingestion creates planning output and may
commit it, so the clean baseline is the attribution and rollback anchor.

Confirm `.planning/` is absent. If it already exists, stop: this is a resume,
repair, or migration, not a first onboarding.

### 5.4 Verify local prerequisites

Run and record:

```text
node --version
npm --version
git --version
codex --version
```

Require Node `>=22.0.0`, npm `>=10.0.0`, functional Git, and Codex
`>=0.130.0` (`>=0.137.0` recommended). If a requirement fails, update that tool
through its approved channel, restart the shell/Codex as needed, and repeat the
entire preflight.

### 5.5 Prepare Firecrawl without persisting its secret

The reviewed project `.codex/config.toml` starts the optional pinned
`firecrawl-mcp@3.22.3` and inherits only the name `FIRECRAWL_API_KEY`. Provide
the value through the launching process environment or an approved secret
manager. Never write it to tracked files, `.env`, `~/.gsd/firecrawl_api_key`,
`.planning/config.json`, profile JSON, shell history, logs, or screenshots.

Do not print the variable to verify it. A harmless provider metadata/search
operation is sufficient after Codex restarts. If Firecrawl is unavailable,
continue with Context7 for current library/CLI documentation and official
primary sources for load-bearing release facts. Mark research degraded rather
than persisting a key or weakening evidence policy.

Keep research credit-efficient: search or map before scraping, scrape the
smallest primary-source set, crawl only a bounded official subsection, reuse
prior evidence, and store concise claims/URLs rather than raw crawls.

### 5.6 Verify Codex hooks and the project skill supply chain

`PostToolUse` is a supported Codex hook event; the event name was not the local
failure. The 2026-07-14 workstation audit found three enabled Claude-oriented
plugins whose hook manifests were not portable to Codex on Windows:
`security-guidance`, `hookify`, and `ralph-loop`. The first registered five
shell handlers distinguished only by Claude-specific `if`/`asyncRewake`
fields, invoked `bash` without `commandWindows`, and passed substituted Windows
paths to WSL even though its wrapper expected Git Bash/MSYS. Those plugins were
removed with Codex's plugin manager. The `mgrep` plugin was also removed: its
executable was absent, its watcher used POSIX-only process control on Windows,
and its code could log the complete inherited environment. Its marketplace,
stale trust state, and known temporary logs were removed too; use Codex's
bundled `rg` search. The duplicate user-scoped Firecrawl entry and stale
npm-global Codex/Firecrawl packages were removed; the reviewed project
Firecrawl pin is now the repository authority. The Firecrawl value was migrated
without disclosure to the Windows user environment. Broad `C:\` trust was
removed while the explicit ReRoom project trust remains.

The project config explicitly keeps
`shell_environment_policy.ignore_default_excludes=false`. Codex therefore
filters shell-tool environment names containing `KEY`, `SECRET`, or `TOKEN` by
default, while the Firecrawl MCP receives only the named `FIRECRAWL_API_KEY`
through its separate `env_vars` declaration. Do not override that shell policy
with broad inheritance. Inert trust records for the removed plugins and a
missing user `hooks.json` were deleted; `features.hooks` remains enabled for
future reviewed, portable hooks.

Fully quit and restart Codex before judging the repair because a running
process retains the hook registry loaded at startup. Then run `codex doctor`
and inspect `codex plugin list`. A hook-bearing plugin is acceptable only after
its current Codex handler schema, every command, timeout, trust hash, and
Windows `commandWindows` path have been reviewed. Do not enable a Claude hook
merely because Codex can parse its `hooks.json`; unsupported conditional fields
can turn a selective hook into an unconditional one. Never use
`--dangerously-bypass-hook-trust` for routine work.

The project-local Apple gap is covered by three copied skills under
`.agents/skills`; `skills-lock.json` records the originally requested source
tags. Those GitHub releases are mutable and their commits are unsigned, so the
tags and CLI `computedHash` values are provenance metadata, not local integrity
proof. The full resolved commits and independently computed LF-normalized tree
digests below are the review anchors. The discovery
and install tool was the MIT `skills@1.5.17` package, npm integrity
`sha512-Mi8P0sy/4rLYESPTCw4tso1hj87zpD3KRVg1iFUlLby2V0+SNAyWNHo/Gq9cruNww8oCSjB9S2hIWtUbVnklcg==`,
run with `DISABLE_TELEMETRY=1`, Codex-only project scope, and copy semantics.
All three skills reported `Safe`, `0 alerts`, and `Low Risk` in the CLI's
Gen/Socket/Snyk snapshot. Those labels are supporting evidence, not a trust
grant; the copied content and scripts remain untrusted code until reviewed for
the task that would invoke them.

| Skill | Audited tag and resolved commit | `SKILL.md` SHA-256 | LF tree SHA-256 | Notice |
|---|---|---|---|---|
| `swiftui-expert-skill` | `AvdLee/SwiftUI-Agent-Skill` `4.0.0`; `65118ba010cbfcd4b985a4c83e29c74f37d1c1f1` | `e74c27b66f5ff5da524ede219348e7f9ddb7602ca9288cc5e3972e8e05e3ba29` | `77468736fd8af123619e9d10d00bf602406f5eecd0707968d986ad7978e8687f` | MIT notice copied from the tag |
| `swift-concurrency` | `AvdLee/Swift-Concurrency-Agent-Skill` `2.1.1`; `faa595ee186dbd23a390dc1e7b06df40948941ab` | `d3cb40aef411f1cfeae4bdd6bc9925a8ad55fdc70804e6d3ffdee188499deb64` | `1dac74c169e426fcc61fb3ebb9c94526438eb7ed2c2b94d4c9e53ea06a2e508e` | MIT notice copied from the tag |
| `swift-testing-expert` | `AvdLee/Swift-Testing-Agent-Skill` `1.2.0`; `798e9b1a2bcac164d4f0c781908199e754f0bab6` | `d039eb55cfbaa379d308ff42c1e459dea355edb869ec0a4d6f488759d2156aec` | `7527c21fdb97ed949e302a1213c644017c70294383f48ce49f249667eeeff45d` | MIT notice copied from the tag |

The tree digest is SHA-256 over each case-insensitively sorted
`relative-path NUL lowercase-file-SHA256 newline` tuple, with the original path
as a deterministic tie-break. Known text files are normalized to LF; binary
assets remain byte-exact. The retained MIT licenses are included, and
`.gitattributes` enforces LF for copied skill text. The SwiftUI tree pin was
recomputed after a clean clone of immutable commit
`65118ba010cbfcd4b985a4c83e29c74f37d1c1f1`; its 41-file copied tree plus the
root MIT notice is byte-identical to the repository copy. The readiness
validator checks every lock entry and skill root, file counts, skill and tree
hashes, required notices, frontmatter, and rejects unlocked roots.

Five additional locked skills are retained as useful project-local convenience
tools. They do not define product behavior, are not shipping dependencies, and
do not gain execution authority from being present. Their lock metadata is
provenance-only; the readiness gate independently pins the copied bytes. Read a
selected `SKILL.md` completely and review any command it proposes before use.

| Supplemental skill | Files | `SKILL.md` SHA-256 | LF-text/binary-exact tree SHA-256 |
|---|---:|---|---|
| `agent-browser` | 1 | `bb6b4c5aae49ff88addb31312437f94242a3e5aae950503ab4f332e28186c261` | `d90860bd424c0888e5ae5e9a52bb1cd96b0ca51725f9e209b7e52b1545509d33` |
| `find-skills` | 1 | `deddc03b4b5f50755b97fcdb737a786676992ef7e9be614d2cd2c71e0320bebf` | `de65c847e3929b71a535f055183e3adc7a3454361ae4f4f9c7bb21d8e0aeb68e` |
| `improve-codebase-architecture` | 3 | `4b4cb798c3863d5b6f5c0b4604af1ecb5beb6df82553c972898a91ba38bcf289` | `b43ea86ec00eef865aa2ce1ddea630ca0a13fae7790298e082c35772b51b759e` |
| `shadcn` | 15 | `a45cddd4511f8262df05b20506f4d52be8210a9ee05a13d9e36d4ee321bab593` | `679eca9603c19c3ae81e13dabe400de0de4889d6bc184b35f69b545abafb9c7c` |
| `vercel-react-best-practices` | 76 | `71ed7794962fa6e803ee83030517b5b93a9f70fbfeb431ec4535c5480a8d8355` | `1eac6c4db59291404dff537eb9607e125fd31ebdc17a5fbc0631e0ec0c5d1b05` |

The SwiftUI skill contains optional local `xctrace` Python helpers; they do not
run automatically. Before an explicit profiling task, review argv, target,
scope, input size, and output paths; never pass secrets through `--env`, use
`--all-processes`, expose unredacted `--list-logs` output, follow a symlinked
output, or treat trace-derived Markdown as trusted instructions. The other two
audited Apple releases contain no executables.

Additional project-local skills are allowed when they solve a concrete project
need and are added deliberately to `skills-lock.json` with local tree pins,
frontmatter validation, executable review, source/license notes, and a full
readiness run. Prefer the locked local copy when a same-name global skill also
exists so behavior is deterministic. Do not refresh or expand the portfolio as
an incidental side effect of another command.
`dpearson2699/swift-ios-skills@realitykit` was deliberately not installed
because its PolyForm Perimeter terms require a separate licensing decision.
Do not run `npx skills install`, `npx skills update`, `npx skills check`, or an
automated lock restore. `skills-lock.json` is provenance-only, not an install
recipe. `skills@1.5.17` follows moving releases, and even `check --help` was
observed refreshing copied trees and removing locally retained notices. Only
the repository readiness validator is an integrity check. A manually reviewed
reinstall must fetch the recorded full commit, retain the audited root license,
normalize text to LF, and reproduce the reviewed tree rather than trusting the
mutable tag. Any skill change requires a new
source/tag/commit/license/script audit, copied notice, lock/tree hash update,
and full readiness run.

This workstation previously had a split global GSD state: a legacy Kimi-style
installation under `~/.agents` was `1.5.0`, while the intended Codex-global
installation under `~/.codex` was `1.6.1`. The older copy predated ReRoom and
was not required by this repository. With explicit authorization on 2026-07-14,
the exact pinned installer first reconciled that copy to `1.6.1`, then its
runtime- and path-scoped uninstaller removed the Kimi/`.agents` GSD core,
69 `gsd-*` skills, agent definition, manifest, and owned script files. The two
named GSD migration residues left by the uninstaller were removed separately
after resolving and validating both targets beneath `~/.agents`. All 85
unrelated `.agents` skill directories remained present.

The sole user-global GSD surface is now `~/.codex` at `1.6.1`, with 69 GSD
skills. The user-level defaults contain no model or effort overrides and no
secret-like keys. The intended final topology is this Codex-global surface plus
the ReRoom-local `.codex` surface installed in section 6; project-local
`.agents/skills` remain separately locked tooling, not another GSD install.
Fully restart Codex before trusting the skill picker or installing the local
surface because a running process retains its previously loaded skill registry.
Future reappearance or version drift is a stop condition: use the exact pinned,
runtime- and scope-specific installer/uninstaller, inspect its manifest and
output, and do not broadly delete user-home state.

## 6. Install and discover stable GSD

From the clean repository root, run exactly:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

Review every path and installer message. Expected project-local output is under
`.codex/skills/gsd-*` plus supported agent/config/hook assets. The installer may
also initialize user-scoped `~/.gsd/defaults.json` (including
`resolve_model_ids: "omit"` on non-Claude runtimes); inspect and record that
side effect without exposing unrelated user data.

The first reviewed Codex-local installation on 2026-07-14 exposed two stable
`1.6.1` projection defects that the tracked local baseline hardens. The
installer removed the existing `[agents]` concurrency bounds while registering
the 34 GSD agents, so `.codex/config.toml` restores `max_threads = 3` and
`max_depth = 1`. It also installed `gsd-check-update.js` without the worker it
spawns. The baseline therefore includes the worker and managed-hook registry
from the exact pinned npm package (source SHA-256 values
`16f4ebb94930af55555534c21c7586327d4756b9cd10cc05350bd4de2a552fd9`
and `ea876b1ec185173e064ebe503c5d05c4782c1a6c9deeffa2bfe91bb8fcd16941`),
with the worker version marker rendered to `1.6.1`; its tracked rendered hash is
`9ad1973af7fc531ef5ed1667207ea73e8bfcc163a07a0659f3a337e639c1b166`.
All four hook registrations use explicit Windows commands and ten-second
timeouts. After any reinstall, inspect these exact properties before restart;
do not assume the installer preserved them and do not bypass hook trust.

Before relying on the ReRoom profile, inspect `~/.gsd/defaults.json` locally for
non-empty `model_overrides` or `effort.agent_overrides`. Stable `1.6.1` merges
those global maps into project settings, so an empty project map cannot cancel
them. Back up and remove global overrides through explicit user review, or
record that they are intentionally accepted. Repository automation must never
silently edit this user-scoped file, and the inspection must not print secrets
or unrelated values into logs.

Fully exit Codex and launch a new process from the environment holding any
required secret. Do not rely on `codex --reload`; it is not in the supported
Codex CLI surface verified for this pin.

Review the repository path and `.codex/config.toml` before granting project
trust. Trust permits project config, MCP, and skills to load; it does not make
external content trustworthy.

In Codex's `$` skill picker, confirm at least:

- `gsd-ingest-docs`;
- `gsd-settings`;
- `gsd-health`;
- `gsd-progress`;
- `gsd-discuss-phase`;
- `gsd-plan-phase`;
- `gsd-execute-phase`;
- `gsd-verify-work`.

If they are missing, verify the repository/trust state, inspect `.codex/skills`,
rerun the exact pinned local installer, fully restart Codex, and check again.
Do not improvise a direct workflow call.

The installer has now changed project-local `.codex/` state, so establish a
second reviewed baseline before ingestion:

```text
git status --short
git diff -- .codex
```

Inspect every installed skill, agent, config, and hook change. Commit those
reviewed tooling changes as a dedicated local baseline, or preserve them through
another explicitly approved non-destructive method, then require
`git status --short` to be empty. Record this post-install commit. The earlier
pre-install commit is not a valid attribution anchor for ingestion after the
installer has mutated `.codex/`.

## 7. Perform the docs-first onboarding

The first GSD invocation for this repository is exactly:

```text
$gsd-ingest-docs --mode new --manifest docs/gsd/ingest-manifest.yml
```

Do not precede or follow it with `$gsd-new-project`; successful `new` ingestion
creates the initial project corpus. Do not use `$gsd-onboard` (absent in stable
`1.6.1`) or initial `$gsd-map-codebase` (the stable workflow says to skip it for
greenfield/no-code repositories).

The manifest disables heuristic directory discovery. Before approval, verify
the exact discovered list has 28 entries and only the reviewed repository-
relative paths. Authority is encoded as:

1. canonical human locks: precedence `-10`;
2. accepted ADRs: `0`;
3. provisional ADRs: `10`;
4. specification and contracts: `20`;
5. PRD: `30`;
6. supporting canonical documents: `40`.

The stable `--resolve` default is `auto`; spelling it adds nothing. It does not
bypass human gates: the classified source list still requires approval,
`BLOCKERS` withhold final project files, `WARNINGS` require approval, and a
locked-vs-locked contradiction cannot be auto-resolved.

Bootstrap limitation: this first ingestion runs before project
`.planning/config.json` exists, so its classification, synthesis, and initial
roadmapping use the pinned installer's effective global/default Codex routing,
not either ReRoom profile or the 34-agent mixes listed above. Accept that only
because the manifest/precedence are immutable and every discovery, warning, and
blocker has a human gate. Do not hand-create planning config or use an
unvalidated settings-before-ingest sequence to disguise this limitation. The
ReRoom profile becomes authoritative only after successful ingestion, config
materialization, reinstallation, restart, and effective-state verification.

After the invocation:

1. inspect all staged `.planning/intel/` evidence;
2. read `.planning/INGEST-CONFLICTS.md` completely;
3. resolve each `BLOCKERS` item in canonical source documents with the required
   human decision--never patch generated output to hide it;
4. rerun the exact ingest command after reviewed source corrections;
5. approve warnings only when the selected authority and rationale are correct;
6. require and review `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`,
   and `STATE.md`;
7. verify stable requirement IDs, accepted-ADR precedence, constraints, risk
   gates, and test traceability survived synthesis.

Partial staged intelligence is useful diagnostic evidence. Preserve it when a
run stops; do not delete it merely to make a retry look clean.

## 8. Materialize config and apply the default profile

Document ingestion does not guarantee `.planning/config.json`. After a
blocker-free ingestion, if config is absent, invoke:

```text
$gsd-settings
```

Let the pinned release create and normalize the active config. Do not fabricate
one and do not rerun project initialization. When stable `$gsd-settings` asks
whether to save these settings as defaults for all new projects, answer **No**.
Answering Yes writes user-scoped `~/.gsd/defaults.json` and can contaminate other
projects or future model routing. The reviewed ReRoom overlay replaces the
temporary project choices next.

Preview the default overlay:

```text
python scripts/apply_gsd_profile.py quality-fast
```

The utility reads only the generated config and selected reviewed profile,
refuses symlinked/out-of-repository paths, malformed JSON, secret-like keys, and
credential-shaped values such as URL userinfo/auth tokens/private keys. It prints
a complete sorted diff and waits for the exact word `apply`. On approval it
rechecks that config bytes are unchanged, creates an exact reviewed-byte UTC
sibling such as `.planning/config.json.backup-20260714T120000Z`, rechecks before
atomic replacement, and performs best-effort concurrent-edit detection before
the replace. No portable file check can eliminate an uncooperative check/replace
race, so do not run another config writer concurrently. Any other response
cancels. `--yes` exists for a separately reviewed automation path; interactive
use is preferred.

For deterministic Codex routing, the utility replacement-assigns the profile's
empty `models`, `model_overrides`, and `model_profile_overrides` maps,
`granularities`, and `effort.agent_overrides`; it also removes stale project
`model_policy`, `dynamic_routing`, and `fast_mode` controls. It preserves
unrelated generated config. This project cleanup cannot override the global
maps described above, so recheck `~/.gsd/defaults.json` before materialization.

The utility changes only root `.planning/config.json`. Stable GSD applies an
active workstream's overlay after root config, so a later workstream can still
override profile values. No workstream exists during first onboarding. If
`GSD_WORKSTREAM` is active or any workstream config exists, the utility refuses
root-only application. Deliberately align or deactivate the overlay first, then
confirm with `$gsd-health` and the rematerialized Codex agent TOML rather than
the root file alone.

The Codex installer materializes static agent model/reasoning TOML from config
at installation time. After applying or switching a profile, rerun the exact
pinned installer and fully restart Codex so the active `model_profile`, effort,
and related settings reach those agents:

```text
npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full
```

Then run:

```text
$gsd-health
$gsd-progress
```

Review `.planning/config.json` without printing environment variables. Confirm
the selected profile values, `mode=interactive`,
`workflow.auto_advance=false`, `workflow.use_worktrees=false`, and the absence
of unsupported/secret-bearing keys. Inspect `git status --short` and every
GSD-created commit or changed path before accepting it.

## 9. Continue the project

Start every new session with repository status and GSD's own state:

```text
git status --short
$gsd-progress
```

If the previous session deliberately paused, resume its handoff first:

```text
$gsd-resume-work
$gsd-progress
```

Use the roadmap phase number reported by progress. The normal reviewed loop is:

```text
$gsd-discuss-phase N
$gsd-ui-phase N
$gsd-plan-phase N --mvp
```

Stop after reviewing the phase plans. Obtain a separate, explicit human
authorization for product implementation in this phase. Onboarding and planning
approval do not imply it. Only after that authorization continue with:

```text
$gsd-execute-phase N
$gsd-code-review N --depth=standard
$gsd-verify-work N
```

`$gsd-ui-phase N` is conditional on a user-facing phase. Under the `quality`
profile, request deep review instead:

```text
$gsd-code-review N --depth=deep
```

When verification finds gaps, correct only the recorded gaps and re-verify:

```text
$gsd-execute-phase N --gaps-only
$gsd-verify-work N
```

Do not use autonomous progression or `progress --next --auto` for this
human-locked project. Plain `$gsd-progress` reports state and a recommended next
action without silently crossing phase gates.

To stop safely mid-work:

```text
$gsd-pause-work
```

The stable command writes `.continue-here.md` and creates a WIP commit. Inspect
that commit. The next session uses `$gsd-resume-work` as shown above. Reinvoking
verification resumes its UAT state rather than inventing a fresh result.

`$gsd-ship N` can create remote/PR effects and is forbidden until verification
passes and a human explicitly authorizes that external mutation. After the last
merged phase, milestone audit/completion are separate reviewed actions:

```text
$gsd-audit-milestone 1.0
$gsd-complete-milestone 1.0
```

Completion can include commit, tag, and push gates; approval for each external
effect must be explicit.

After significant implementation exists, `$gsd-map-codebase` can become useful
for refreshing codebase context. It is not part of initial onboarding.

## 10. Switch profiles deliberately

Switch to maximum quality before architecture commitments, accepted ADR or
contract changes, security/privacy-sensitive work, schema/data migrations,
release decisions, kill gates, or an unresolved correctness failure:

```text
python scripts/apply_gsd_profile.py quality
```

Review the entire diff and type `apply`. Rerun the exact pinned installer and
fully restart Codex before relying on rematerialized agent settings.

Return to the normal profile after the bounded high-assurance work:

```text
python scripts/apply_gsd_profile.py quality-fast
```

Again review, apply, reinstall the pin, and restart. Each switch creates a
timestamped config backup.

## 11. Recovery and rollback

- Profile mistake: inspect and restore the selected
  `.planning/config.json.backup-<UTC>` sibling, then rerun the exact pinned
  installer and restart Codex if static agents were materialized.
- Ingest commit: inspect it and use `git revert <commit-sha>`; the GSD undo
  command targets plan/phase manifests, not initial docs ingestion.
- Completed plan/phase: use the stable, dependency-checking `$gsd-undo` surface
  (`--last`, `--plan`, or `--phase`) only after reviewing its proposed revert.
- Partial planning: preserve `.planning/` and conflict/intel evidence for
  diagnosis. Never erase it blindly.
- Broken local installation: rerun the exact pinned installer. If an explicit
  uninstall is required, use
  `npx --yes @opengsd/gsd-core@1.6.1 --codex --local --uninstall`, inspect the
  removed surface, and preserve planning artifacts.

Never use `git reset --hard` or an unreviewed recursive delete as recovery.

## 12. Troubleshooting

**Skills missing after install** -- verify the repository path/trust state and
`.codex/skills`, rerun the exact pin, fully restart Codex, and check the `$`
picker.

**Manifest path/type failure** -- fix the reviewed canonical source or manifest;
do not enable discovery or add archives, audits, prompts, raw research, or this
setup guide as a shortcut.

**Ingest stops with blockers** -- read the conflict report and staged intel,
resolve authority in canonical source documents, obtain the required human
decision, and rerun the same command. Do not switch initializer commands.

**Config absent** -- after successful ingestion, use `$gsd-settings` once.

**Profile utility refuses config** -- remove malformed, symlinked, non-object,
or secret-bearing state through review. Do not bypass the utility with a raw
copy of the profile.

**Config and Codex agents disagree** -- confirm the active overlay, rerun the
exact pinned installer, fully restart Codex, then run health/progress again.

**Firecrawl unavailable** -- fix provider/secret injection without printing or
persisting the key; otherwise use approved primary-source retrieval and mark
research degraded.

## 13. Upgrade policy

Do not routinely run `$gsd-update`: stable `1.6.1` update logic targets
`@latest`, which violates this repository's immutable pin discipline. To inspect
availability without changing state, use:

```text
npm view @opengsd/gsd-core dist-tags --json
```

A future upgrade requires a new review of the exact release/tag/commit and npm
integrity, engines, installer side effects, Codex integration, commands,
normalization/migration behavior, schema/default manifests, every first-party
capability registry, model catalog, hooks, and both profile key sets. Update the
pin only after the repository validator and onboarding guide are revised and
all readiness checks pass. Never change just the version string.

## 14. Primary sources used for this contract

- [OpenGSD overview](https://opengsd.net/)
- [Current GSD introduction](https://docs.opengsd.net/core/introduction)
- [Current installation guide](https://docs.opengsd.net/core/installation)
- [Current settings reference](https://docs.opengsd.net/core/configuration/settings)
- [Current model-profile reference](https://docs.opengsd.net/core/configuration/model-profiles)
- [Current integration reference](https://docs.opengsd.net/core/configuration/integrations)
- [Current context/ingest command guide](https://docs.opengsd.net/core/commands/context-commands)
- [Current existing-document project guide](https://docs.opengsd.net/core/guides/new-project)
- [Current phase lifecycle](https://docs.opengsd.net/core/guides/phase-lifecycle)
- [Official npm metadata for `1.6.1`](https://registry.npmjs.org/@opengsd%2Fgsd-core/1.6.1)
- [Immutable `v1.6.1` release](https://github.com/open-gsd/gsd-core/releases/tag/v1.6.1)
- [Immutable `1.6.1` package manifest](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/package.json)
- [Immutable installer](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/bin/install.js)
- [Immutable configuration schema](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/config-schema.manifest.json)
- [Immutable configuration defaults](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/config-defaults.manifest.json)
- [Immutable Codex model catalog](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/model-catalog.json)
- [Immutable model resolver](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/src/model-resolver.cts)
- [Immutable config loader](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/src/config-loader.cts)
- [Immutable Codex capability definition](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/codex/capability.json)
- [Immutable capability trust implementation](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/src/capability-trust.cts)
- [Immutable docs-ingest command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/ingest-docs.md)
- [Immutable docs-ingest workflow](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/workflows/ingest-docs.md)
- [Immutable settings command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/settings.md)
- [Immutable progress command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/progress.md)
- [Immutable discuss command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/discuss-phase.md)
- [Immutable UI command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/ui-phase.md)
- [Immutable plan command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/plan-phase.md)
- [Immutable execute command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/execute-phase.md)
- [Immutable code-review command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/code-review.md)
- [Immutable verify command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/verify-work.md)
- [Immutable ship command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/ship.md)
- [Immutable pause command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/pause-work.md)
- [Immutable resume command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/resume-work.md)
- [Immutable update command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/update.md)
- [Immutable undo command](https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/commands/gsd/undo.md)
- [Official Codex skills documentation](https://developers.openai.com/codex/build-skills)
- [Official Codex configuration reference](https://developers.openai.com/codex/config-reference)
- [Official Codex AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md)
- [Official Codex hooks documentation](https://developers.openai.com/codex/hooks)
- [Codex `0.144.3` release](https://github.com/openai/codex/releases/tag/rust-v0.144.3)
- [Codex `0.144.3` Windows hook command runner](https://github.com/openai/codex/blob/78ad6e6bfd1d3b6a209acd3ef82172a96b25179c/codex-rs/hooks/src/engine/command_runner.rs)
- [Codex `0.144.3` hook discovery and Windows-command selection](https://github.com/openai/codex/blob/78ad6e6bfd1d3b6a209acd3ef82172a96b25179c/codex-rs/hooks/src/engine/discovery.rs)
- [Codex `0.144.3` supported hook-handler schema](https://github.com/openai/codex/blob/78ad6e6bfd1d3b6a209acd3ef82172a96b25179c/codex-rs/config/src/hook_config.rs)
- [Codex AGENTS.md loader at `0.144.3`](https://github.com/openai/codex/blob/78ad6e6bfd1d3b6a209acd3ef82172a96b25179c/codex-rs/core/src/agents_md.rs)
- [Official Firecrawl MCP documentation](https://docs.firecrawl.dev/mcp-server)
- [Skills CLI source and reference](https://github.com/vercel-labs/skills)
- [Skills CLI documentation](https://skills.sh/docs/cli)
- [npm metadata for `skills@1.5.17`](https://registry.npmjs.org/skills/1.5.17)
- [SwiftUI skill resolved commit](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/65118ba010cbfcd4b985a4c83e29c74f37d1c1f1)
- [SwiftUI skill MIT notice](https://github.com/AvdLee/SwiftUI-Agent-Skill/blob/65118ba010cbfcd4b985a4c83e29c74f37d1c1f1/LICENSE)
- [Swift Concurrency skill resolved commit](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/tree/faa595ee186dbd23a390dc1e7b06df40948941ab)
- [Swift Concurrency skill MIT notice](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/faa595ee186dbd23a390dc1e7b06df40948941ab/LICENSE)
- [Swift Testing skill resolved commit](https://github.com/AvdLee/Swift-Testing-Agent-Skill/tree/798e9b1a2bcac164d4f0c781908199e754f0bab6)
- [Swift Testing skill MIT notice](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/798e9b1a2bcac164d4f0c781908199e754f0bab6/LICENSE)

Context7 was used for current GSD documentation discovery, and Firecrawl was
used to retrieve current official pages and official registry/source evidence.
Moving documentation was treated as untrusted evidence and reconciled against
the immutable stable release before any command or config key entered this
guide.
