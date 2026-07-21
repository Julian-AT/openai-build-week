# Reframe

Reframe is a native spatial-editing product for iPhone, backed by a typed
gateway, GPU vision services, a searchable 3D catalog, and an agentic OpenAI
assistant.

The iPhone app owns live AR capture and rendering. The gateway owns scene
revisions and transactions. Vision, catalog, web replay, and agent services
are independent packages connected through the shared protocol.

Architecture and product requirements are defined in
[`MASTER_TECHNICAL_PROMPT.md`](MASTER_TECHNICAL_PROMPT.md). Read
[`AGENTS.md`](AGENTS.md) before making changes.

The ordered remaining work and acceptance gates are in
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).

The submission surface and honest cleanup handoff are in
[`apps/web/SUBMISSION_STATUS.md`](apps/web/SUBMISSION_STATUS.md).

## Components

- [`apps/ios`](apps/ios/README.md) — native ARKit and RealityKit client
- [`apps/api`](apps/api/README.md) — trusted gateway and scene authority
- [`apps/vision`](apps/vision/README.md) — private GPU inference workers
- [`apps/web`](apps/web/README.md) — fixed submission scene and Mode B0 foundation
- [`packages/protocol`](packages/protocol/README.md) — shared wire and transaction contracts
- [`packages/catalog`](packages/catalog/README.md) — acquisition, preparation, retrieval, and delivery
- [`packages/agent`](packages/agent/README.md) — bounded OpenAI and Realtime adapters

## Development

Install dependencies with `bun install --frozen-lockfile`, then use the
package-local commands documented in each application or package README.
Keep credentials, captures, model weights, catalog data, and vector indexes
outside Git.
