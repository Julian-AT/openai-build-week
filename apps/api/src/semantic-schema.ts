const stringConstraintSchema = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "value"],
  properties: {
    kind: { enum: ["color_tag", "style_tag"] },
    value: { type: "string", minLength: 1, maxLength: 64 },
  },
} as const;

const booleanConstraintSchema = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "value"],
  properties: {
    kind: { enum: ["preserve_walkway", "support_required"] },
    value: { type: "boolean" },
  },
} as const;

const numberConstraintSchema = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "value"],
  properties: {
    kind: { const: "max_footprint_m2" },
    value: { type: "number", exclusiveMinimum: 0, maximum: 20 },
  },
} as const;

export const TYPED_CONSTRAINT_SCHEMA = {
  anyOf: [stringConstraintSchema, booleanConstraintSchema, numberConstraintSchema],
} as const;

const constraintsSchema = {
  type: "array",
  maxItems: 8,
  items: TYPED_CONSTRAINT_SCHEMA,
  description:
    "Constraints must be unique and sorted lexicographically by kind plus U+0000 plus the JCS constraint object.",
} as const;

const catalogArgumentsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["asset_id"],
  properties: {
    asset_id: {
      enum: [
        "asset_53000000-0000-4000-8000-000000000002",
        "asset_53000000-0000-4000-8000-000000000003",
        "asset_53000000-0000-4000-8000-000000000004",
      ],
    },
  },
} as const;

const emptyArgumentsSchema = {
  type: "object",
  additionalProperties: false,
  properties: {},
  required: [],
} as const;

function operationSchema(
  operation: "place" | "replace" | "remove" | "restore",
  argumentsSchema: typeof catalogArgumentsSchema | typeof emptyArgumentsSchema,
) {
  return {
    type: "object",
    additionalProperties: false,
    required: ["operation", "arguments", "constraints"],
    properties: {
      operation: { const: operation },
      arguments: argumentsSchema,
      constraints: constraintsSchema,
    },
  } as const;
}

export const SEMANTIC_INTENT_SCHEMA = {
  anyOf: [
    operationSchema("place", catalogArgumentsSchema),
    operationSchema("replace", catalogArgumentsSchema),
    operationSchema("remove", emptyArgumentsSchema),
    operationSchema("restore", emptyArgumentsSchema),
  ],
} as const;

export const MODEL_PROPOSAL_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["status", "intent", "explanation", "clarification"],
  properties: {
    status: { enum: ["ready", "needs_clarification"] },
    intent: { anyOf: [SEMANTIC_INTENT_SCHEMA, { type: "null" }] },
    explanation: { type: "string", minLength: 1, maxLength: 280 },
    clarification: {
      anyOf: [{ type: "string", minLength: 1, maxLength: 280 }, { type: "null" }],
    },
  },
} as const;
