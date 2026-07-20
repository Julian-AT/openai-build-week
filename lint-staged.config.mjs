export default {
  "{apps/api,apps/web,packages/agent,packages/catalog,packages/protocol}/**/*.{js,mjs,cjs,ts,tsx,json,jsonc,css}":
    "biome check --write --no-errors-on-unmatched",
  "apps/vision/**/*.py": [
    "uv run --project apps/vision --frozen ruff check --fix",
    "uv run --project apps/vision --frozen ruff format",
  ],
  "apps/ios/**/*.swift": "xcrun swift-format lint --strict",
};
