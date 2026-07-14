# ReRoom

Repository stage: **PRE-GSD READY**

ReRoom is a documentation-only specification for a controlled camera-feed AR room editor. The planned native iPhone hero uses ARKit authority to place, replace, remove, and restore a chair/small-table edit; a separate Next.js Mode B0 client provides deterministic replay, debugging, fallback, sessions, and sharing. No product feature described here has been implemented yet.

## Canonical authority

Start with [the canonical index](docs/canonical/README.md). Precedence is:

1. human-locked decisions;
2. Accepted ADRs;
3. Provisional ADRs within their benchmark/kill gates;
4. the Master Technical Specification and versioned contracts;
5. the PRD;
6. supporting development, test, risk, research, and glossary documents.

Core documents:

- [Product requirements](docs/canonical/PRD.md)
- [Master technical specification](docs/canonical/MASTER_TECHNICAL_SPEC.md)
- [Development strategy](docs/canonical/DEVELOPMENT_STRATEGY.md)
- [Test and evaluation plan](docs/canonical/TEST_AND_EVALUATION_PLAN.md)
- [Risks and kill gates](docs/canonical/RISK_AND_KILL_GATES.md)
- [Research ledger](docs/canonical/RESEARCH_LEDGER.md)
- [Glossary and ID registry](docs/canonical/GLOSSARY_AND_ID_REGISTRY.md)
- [Machine-readable contracts](docs/contracts/README.md)
- [Architecture decisions](docs/adr/)

The original technical plan and PRD are preserved byte-for-byte under [the source archive](docs/archive/README.md). They are historical evidence, not current implementation authority. Audit reports under `docs/audit/` explain the changes but are excluded from GSD ingestion.

## Validate this preparation

No product/runtime dependency installation is required for validation. From the
repository root, run one of:

```text
python scripts/check_no_secrets.py
python scripts/verify_pre_gsd_readiness.py
```

On a POSIX shell, the complete readiness check also has a thin wrapper:

```text
sh scripts/verify-pre-gsd-readiness.sh
```

The verifier checks archives and hashes, required documents, manifest paths, JSON/Schema/TOML/YAML syntax, P0 requirement structure, ADR/provisional gates, research coverage, GSD profile keys, terminology/scope, secrets, the absence of product code, and the absence of `.planning/`.

## GSD status and exact next step

GSD Core has **not** been installed project-locally or run for this repository,
and `.planning/` does not exist. An older user-global GSD `1.5.0` surface is a
documented onboarding stop condition. Three pinned, license-reviewed
project-local Codex skills cover the native Swift gap; they are agent tooling,
not product/runtime/build dependencies. No model weight, cloud resource,
product implementation, commit, push, or PR was created by this preparation.

After all readiness checks pass, the exact first human action is to explicitly authorize the GSD onboarding run and confirm [the onboarding guide's complete preflight](docs/gsd/ONBOARDING_AND_CONTINUATION.md#5-preflight-before-the-first-run). Do not execute an onboarding command before that authorization. The first subsequent shell action is to establish a clean Git baseline beginning with:

```text
git status --short
```

Do not proceed unless the result is clean and every other preflight condition passes. The exact first GSD invocation later in that guide is:

```text
$gsd-ingest-docs --mode new --manifest docs/gsd/ingest-manifest.yml
```

Do not run it during PRE-GSD preparation and do not begin product implementation from this README.
