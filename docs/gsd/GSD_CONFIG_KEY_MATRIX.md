# GSD v1.6.1 configuration key matrix

Profile values are shown as `quality-fast / maximum-assurance`. “Stable support” means the key was found in the pinned central manifest or a released first-party capability registry at commit `1c352d1ea37b010e99b8353905eb5def4f784100`; it does not mean a similarly named prose-only key is valid.

| Key | Profile value | Purpose | Quality impact | Speed/cost impact | Stable-version support | Primary source |
|---|---|---|---|---|---|---|
| `mode` | `interactive / interactive` | Keep workflow under operator control. | Prevents silent autonomous transitions. | Adds human wait points. | Yes — central schema. | [Schema][schema] |
| `runtime` | `codex / codex` | Select Codex-aware behavior and catalog resolution. | Avoids runtime-incompatible agents/settings. | Neutral. | Yes — central schema. | [Schema][schema] |
| `model_profile` | `balanced / quality` | Choose a released runtime-aware model tier. | Assurance raises reasoning quality. | `quality` costs more and may be slower. | Yes — central schema and model catalog. | [Schema][schema], [Catalog][catalog] |
| `models.planning` | `opus / opus` | Select the stable high tier for planning. | Maximizes architecture-sensitive plan reasoning. | Higher model cost/latency. | Yes — dynamic central-schema key; tier resolved for Codex. | [Schema][schema], [Resolver][resolver] |
| `models.discuss` | `opus / opus` | Select the stable high tier for discussion. | Improves assumption and decision quality. | Higher model cost/latency. | Yes — dynamic central-schema key; tier resolved for Codex. | [Schema][schema], [Resolver][resolver] |
| `models.research` | `opus / opus` | Select the stable high tier for research synthesis. | Improves evidence reconciliation. | Higher retrieval synthesis cost/latency. | Yes — dynamic central-schema key; tier resolved for Codex. | [Schema][schema], [Resolver][resolver] |
| `models.execution` | `sonnet / opus` | Use a capable normal tier or high assurance tier during execution. | Assurance increases reasoning on critical implementation. | Normal is faster; assurance costs more. | Yes — dynamic central-schema key; tier resolved for Codex. | [Schema][schema], [Resolver][resolver] |
| `models.verification` | `opus / opus` | Select the stable high tier for verification. | Strengthens adversarial validation and failure diagnosis. | Higher model cost/latency. | Yes — dynamic central-schema key; tier resolved for Codex. | [Schema][schema], [Resolver][resolver] |
| `models.completion` | `sonnet / opus` | Use capable summaries normally and high-tier synthesis in assurance mode. | Keeps normal handoffs high-signal; assurance maximizes completeness. | Normal is faster; assurance costs more. | Yes — dynamic central-schema key; tier resolved for Codex. | [Schema][schema], [Resolver][resolver] |
| `granularity` | `standard / fine` | Set the default decomposition detail. | Fine mode increases explicitness. | Fine creates more planning/review work. | Yes — central schema. | [Schema][schema] |
| `granularities.planning` | `fine / fine` | Override planning detail. | Produces smaller, auditable plan units. | More plan tokens/time. | Yes — central schema. | [Schema][schema] |
| `granularities.discuss` | `fine / fine` | Override discussion detail. | Surfaces assumptions and decisions. | More discussion tokens/time. | Yes — central schema. | [Schema][schema] |
| `granularities.research` | `fine / fine` | Override research detail. | Improves source/claim coverage. | More retrieval and synthesis. | Yes — central schema. | [Schema][schema] |
| `granularities.execution` | `standard / standard` | Keep implementation chunks coherent. | Avoids over-fragmented execution. | Balanced throughput. | Yes — central schema. | [Schema][schema] |
| `granularities.verification` | `standard / fine` | Control verification decomposition. | Assurance checks narrower claims. | Fine verification is slower. | Yes — central schema. | [Schema][schema] |
| `granularities.completion` | `fine / fine` | Make completion evidence explicit. | Reduces missed handoff items. | Small completion overhead. | Yes — central schema. | [Schema][schema] |
| `parallelization` | `true / false` | Enable or disable released parallel workflow behavior. | Serial assurance reduces concurrency races. | Enabled is faster; disabled is slower. | Yes — top-level boolean. Subkeys are not valid. | [Schema][schema], [Loader][loader] |
| `workflow.research` | `true / true` | Run the research capability where workflow calls for it. | Adds current, cited evidence. | Retrieval/token cost. | Yes — capability-owned key. | [Research][research] |
| `workflow.plan_check` | `true / true` | Review plans before execution. | Catches feasibility and coverage defects. | Adds a review pass. | Yes — central/capability configuration. | [Schema][schema] |
| `workflow.verifier` | `true / true` | Verify outcomes against plans/requirements. | Prevents “implemented” from meaning “assumed.” | Adds verification work. | Yes — central schema. | [Schema][schema] |
| `workflow.auto_advance` | `false / false` | Stop automatic phase transitions. | Preserves deliberate human gates. | Requires operator continuation. | Yes — central schema. | [Schema][schema] |
| `workflow.nyquist_validation` | `true / true` | Require validation coverage appropriate to changed behavior. | Reduces untested requirement edges. | Adds test/validation planning. | Yes — capability-owned key. | [Nyquist][nyquist] |
| `workflow.post_planning_gaps` | `true / true` | Detect missing coverage after planning. | Finds orphaned requirements/risks. | Adds gap-analysis pass. | Yes — capability-owned key. | [Gap][gap] |
| `workflow.node_repair` | `true / true` | Allow bounded repair of defective plan graph nodes. | Improves plan graph integrity. | Can add repair iterations. | Yes — central schema. | [Schema][schema] |
| `workflow.node_repair_budget` | `2 / 2` | Cap automatic repair attempts. | Avoids accepting unresolved graph defects. | Bounds cost and looping. | Yes — central schema. | [Schema][schema] |
| `workflow.human_verify_mode` | `end-of-phase / mid-flight` | Choose when human verification occurs. | Mid-flight catches divergence earlier. | Mid-flight interrupts more often. | Yes; allowed values include both selections. | [Schema][schema] |
| `workflow.research_before_questions` | `false / true` | Research before asking the operator. | Assurance questions arrive with evidence. | Enabled adds latency/retrieval. | Yes — research capability key. | [Research][research] |
| `workflow.discuss_mode` | `assumptions / assumptions` | Let discussion proceed from documented assumptions. | Makes inferred decisions reviewable. | Faster than mandatory interview flow. | Yes; stable values include `discuss` and `assumptions`. | [Schema][schema] |
| `workflow.max_discuss_passes` | `2 / 3` | Bound iterative discussion. | Extra assurance pass can expose ambiguity. | Higher value costs more time/tokens. | Yes — central schema. | [Schema][schema] |
| `workflow.skip_discuss` | `false / false` | Retain phase discussion. | Preserves intent/constraint clarification. | Adds discussion step. | Yes — central schema. | [Schema][schema] |
| `workflow.use_worktrees` | `false / false` | Avoid unsupported Codex worktree path. | Prevents runtime/path divergence. | Gives up worktree isolation. | Yes; `true` is not selected for Codex v1.6.1. | [Schema][schema], [Commands][commands] |
| `workflow.code_review` | `true / true` | Enable first-party code review. | Finds correctness and maintainability defects. | Adds reviewer time/tokens. | Yes — capability-owned key. | [Code review][code-review] |
| `workflow.code_review_depth` | `standard / deep` | Select review intensity. | Deep review broadens assurance. | Deep is slower/more expensive. | Yes; stable values are `quick`, `standard`, `deep`. | [Code review][code-review] |
| `workflow.plan_review_convergence` | `default/absent / true` | Require cross-review convergence in assurance mode. | Raises confidence in critical plans. | Adds review iterations/model cost. | Yes — released plan-review control. | [Schema][schema] |
| `workflow.ui_phase` | `true / true` | Enable UI-specific design contract work. | Keeps interaction/visual requirements explicit. | Adds UI planning. | Yes — UI capability key. | [UI][ui] |
| `workflow.ui_review` | `true / true` | Enable UI-specific review. | Detects visual/interaction regressions. | Adds review work. | Yes — UI capability key. | [UI][ui] |
| `workflow.ui_safety_gate` | `true / true` | Enforce UI capability safety checks. | Protects accessibility and high-risk interaction constraints. | Adds a gate/check. | Yes — UI capability key. | [UI][ui] |
| `workflow.context_coverage_gate` | `true / true` | Require adequate context coverage before progression. | Reduces plans based on partial repository knowledge. | Adds analysis/checking. | Yes — released config key. | [Schema][schema] |
| `workflow.context_guard_mode` | `warn / auto` | Set context-pressure response. | Auto mode more strongly protects continuity. | Auto may pause/chunk sooner. | Yes; stable values are `auto`, `warn`, `off`. | [Schema][schema] |
| `workflow.security_enforcement` | `true / true` | Enable security capability enforcement. | Promotes threat/control checks. | Adds security analysis. | Yes — security capability key. | [Security][security] |
| `workflow.security_asvs_level` | `1 / 2` | Set OWASP ASVS assurance target. | Level 2 broadens control expectations. | Level 2 costs more review/testing. | Yes; stable values are `1`, `2`, `3`. | [Security][security] |
| `workflow.security_block_on` | `high / medium` | Set severity that blocks progression. | Medium threshold is stricter. | Stricter threshold creates more remediation. | Yes; `critical`, `high`, `medium`, `low`, `none`. | [Security][security] |
| `plan_review.source_grounding` | `true / true` | Require plans to cite repository evidence. | Reduces invented paths/APIs/contracts. | Adds evidence lookup. | Yes — central schema. | [Schema][schema] |
| `plan_review.source_grounding_authority` | `grep / grep` | Choose the stable evidence authority. | `grep` provides concrete repository grounding. | Small lookup cost. | Yes; `grep` and `intel` are effective in this release. | [Schema][schema], [Loader][loader] |
| `hooks.context_warnings` | `true / true` | Enable installed context-monitor warnings. | Warns before context degradation harms continuity. | Negligible; may prompt handoff/chunking. | Yes — central schema and Codex installer path. | [Schema][schema], [Installer][installer] |

## Explicitly excluded settings

The following are not profile omissions by accident:

| Excluded key family | Reason |
|---|---|
| `gates.*` | Documented in places, but rejected by the v1.6.1 canonical validator. |
| `safety.*` | Not a stable valid configuration family. |
| `config.audit.enabled` | Not a stable valid key. |
| `parallelization.enabled` object form | Loader/validator disagreement; top-level boolean is the conservative form. |
| `parallelization.plan_level`, `.task_level`, `.skip_checkpoints`, `.max_concurrent_agents`, `.min_plans_for_parallel` | Not stable schema keys; cannot encode a truthful maximum concurrency of three. |
| `workflow.use_worktrees: true` | Not selected for the pinned Codex runtime path. |
| `security.injection_blocking` | The key exists, but the v1.6.1 Codex installer does not install/register the corresponding read-injection scanner hook. |
| `workflow.plan_chunked` | Valid and useful for exceptionally large or hanging plans, but its outline/per-plan task and commit overhead should be selected per phase rather than imposed globally. |
| Literal `firecrawl`, `brave_search`, or `exa_search` | GSD may mask display but persists string values as plaintext in `.planning/config.json`; use session environment injection only. |
| Explicit model IDs | Released runtime catalog should resolve the selected Codex tier. |

[schema]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/config-schema.manifest.json
[catalog]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/model-catalog.json
[resolver]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/src/model-resolver.cts
[loader]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/src/config-loader.cts
[commands]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/docs/COMMANDS.md
[installer]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/bin/install.js
[research]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/research/capability.json
[nyquist]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/nyquist/capability.json
[gap]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/gap-analysis/capability.json
[code-review]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/code-review/capability.json
[ui]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/ui/capability.json
[security]: https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/capabilities/security/capability.json
