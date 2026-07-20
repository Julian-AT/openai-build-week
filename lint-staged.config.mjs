export default {
  "{apps/api,apps/web,packages/ai,packages/contracts}/**/*.{js,mjs,cjs,ts,tsx,json,jsonc,css}":
    "biome check --write --no-errors-on-unmatched",
  "apps/inference/**/*.py": [
    "uv run --project apps/inference --frozen ruff check --fix",
    "uv run --project apps/inference --frozen ruff format",
  ],
  "apps/ios/**/*.swift": "xcrun swift-format lint --strict",
};
