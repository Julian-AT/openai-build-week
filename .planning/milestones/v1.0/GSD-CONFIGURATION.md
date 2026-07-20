# GSD Configuration Rationale

The checked-in [.planning/config.json](../../config.json) is tuned for the
remaining ReRoom hackathon work, not for unattended bulk generation.

| Setting | Selected value | Reason |
|---|---|---|
| Runtime/profile | `codex` / `balanced` with two overrides | Keeps GSD 1.7 health-clean while preserving the useful split: planning uses Sol, implementation/review uses Terra, and mapping uses Luna. Debugging and security are explicitly promoted to Sol. |
| Model tiers | Sol / Terra / Luna | Heavy planning/security synthesis uses Sol, standard implementation/review uses Terra, and light mapping/checking uses Luna through the GSD role resolver. |
| Reasoning effort | light `low`, standard `high`, heavy `xhigh` | Keeps mechanical checks fast while plans, audits, and security receive depth. |
| Context window | `1000000` | Prevents GSD from prematurely compressing the large canonical/phase surface. |
| Mode | `interactive`; `auto_advance=false` | Human/device/provider gates and contract changes must stop at explicit boundaries. |
| Parallelization | plan-level; max 2; task-level off; checkpoints retained | Matches the two-developer sprint, gains independent-lane speed, and prevents sibling tasks from racing shared Xcode/contracts/planning files. |
| Planning gates | research, plan check, verifier, Nyquist, API coverage, AI integration, UI safety/review | The project crosses contract, native UI, external model, and security boundaries. |
| Quality | TDD, deep code review, ASVS level 2, block on high | Behavior changes require RED→GREEN and high-severity issues cannot be carried into the demo candidate. |
| Context guard | warn | Preserves autonomy while surfacing fracture risk before reasoning degrades. |
| Subagent timeout | 900 seconds | Allows the full Swift package suite and source-bound phase checks to finish without premature cancellation. |
| Graph/intel | off | The current canonical/roadmap surface is already mature; automatic graph/intel churn would not improve the 24-hour exit. |
| Git branching | `none` during the finish run | Keeps current local recovery/AI commits on one candidate line and avoids GSD forking a new phase from stale `origin/HEAD`; use `$gsd-ship` or an explicit human-approved branch at candidate freeze. |

The config intentionally does not use YOLO/auto-chain mode. Fast completion
comes from narrow vertical slices, two-lane concurrency, stable contracts, and
kill rules—not by letting an agent cross physical, publication, or authority
boundaries without review.

## Verified resolver result

Against the pinned GSD 1.7.0 catalog, `gsd-tools resolve-model` reports:

| Role examples | Resolved model |
|---|---|
| planner, security auditor | `gpt-5.6-sol` |
| executor, code reviewer, doc writer | `gpt-5.6-terra` |
| codebase mapper | `gpt-5.6-luna` |

`gsd-tools migrate-config` reports no migration or normalization, and
`config-get parallelization` returns the exact two-agent plan-level policy.

GSD 1.7.0's model catalog and settings workflow list `adaptive`, but its health
validator omits that value and emits `W004`. The checked-in configuration uses
the equivalent health-clean `balanced` base for the roles that matter here and
promotes only the debugger and security auditor explicitly. This avoids a
known internal-validator disagreement without weakening those critical roles.

Machine paths, credentials, API keys, generated agents, and Codex runtime state
do not belong in this file or repository. GSD Core remains globally pinned to
`@opengsd/gsd-core@1.7.0`.
