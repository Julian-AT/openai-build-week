# ReRoom

Status: **GSD 1.7 planning ready; product implementation has not started.**

ReRoom is a controlled camera-grounded room editor. The native SwiftUI iPhone
experience uses ARKit authority to place, replace, remove, and restore one
freestanding chair or small table. A separate Next.js Mode B0 client provides
deterministic replay, inspection, sessions, sharing, typed proposals, and
honest fallback behavior.

## Start on another machine

Install Node.js 22+ and npm 10+, then clone this repository and open a terminal
at its root. Keep `FIRECRAWL_API_KEY` in the user environment, never in the
repository. Add the following global Codex MCP entry to `~/.codex/config.toml`:

```toml
[mcp_servers.firecrawl]
command = "npx"
args = ["--yes", "firecrawl-mcp@3.22.3"]
env_vars = ["FIRECRAWL_API_KEY"]
```

From the repository root, install GSD Core globally for Codex:

```text
npx --yes @opengsd/gsd-core@1.7.0 --codex --global
```

Restart Codex completely, then confirm `codex mcp list` includes `firecrawl`.
GSD's runtime, agents, skills, hooks, and MCP configuration belong in the
user's Codex home; they are intentionally not vendored in this repository.

The repository is already initialized. Do not run `$gsd-new-project` or repeat
new-mode document ingestion. Start with:

```text
$gsd-next
```

GSD 1.7 should route this state to Phase 1 discussion (equivalent to
`$gsd-discuss-phase 1`).

## Planning entry point

The portable project state is entirely under `.planning/`:

- [PROJECT.md](.planning/PROJECT.md) — scope, authority, constraints, and decisions
- [REQUIREMENTS.md](.planning/REQUIREMENTS.md) — 24 P0 and 2 stretch requirements
- [ROADMAP.md](.planning/ROADMAP.md) — eight dependency/risk phases and gate mapping
- [STATE.md](.planning/STATE.md) — current position and continuation state
- [config.json](.planning/config.json) — minimal Codex/GSD settings
- [intel/SYNTHESIS.md](.planning/intel/SYNTHESIS.md) — compact ingest synthesis and limits

The config keeps GSD 1.7's `balanced` role allocation while resolving every
Codex tier to GPT-5.6 Sol. Heavy roles use xhigh effort, standard roles use high,
and light mapping/checking roles use low, preserving speed without changing the
model family. It keeps interactive checkpoints and standard plan granularity,
enables the relevant research, UI, AI, API, review, security, and TDD gates, and
leaves graph updates manual. Firecrawl is enabled through the user environment.

## Product authority

Start with [docs/canonical/README.md](docs/canonical/README.md). Human locks and
Accepted ADRs outrank provisional choices, contracts/specifications, the PRD,
and supporting evidence documents.

The original [Master Technical Plan v3.2](docs/archive/source/ReRoom_Master_Technical_Plan_v3.2.md)
and [PRD v1.0](docs/archive/source/ReRoom_PRD_v1.0.md) remain byte-preserved
historical sources. Their useful content was canonicalized; material corrections
are recorded in [the decision changelog](docs/audit/DECISION_CHANGELOG.md).

No phase description authorizes implementation by itself. Discuss the phase,
review its detailed plan, and preserve the canonical requirement, contract,
gate, security, license, and evidence rules.
