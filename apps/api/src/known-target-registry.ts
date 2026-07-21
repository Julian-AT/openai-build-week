/** Trusted, capture-derived target identity. Model output can only select one
 * of these records; it can never manufacture an object or reveal identifier. */
export interface KnownTarget {
  readonly sessionID: string;
  readonly targetID: string;
  readonly pointerContextID: string;
  readonly languageReferences: readonly string[];
  readonly revealBundleID: string;
  /** RF-COORD-1 row-major world transform captured for the target. */
  readonly worldFromTarget: readonly number[];
  readonly dimensionsM: Readonly<{ width: number; height: number; depth: number }>;
}

export interface KnownTargetRegistry {
  resolve(
    sessionID: string,
    request: {
      readonly pointerContextID: string | null;
      readonly languageReference: string | null;
    },
  ): KnownTarget | null;
}

export function createInMemoryKnownTargetRegistry(
  records: readonly KnownTarget[],
): KnownTargetRegistry {
  const validated = records.map((record) => freezeTarget(record));
  return {
    resolve(sessionID, request) {
      if (request.pointerContextID === null && request.languageReference === null) return null;
      const language = normalizeLanguageReference(request.languageReference);
      const matches = validated.filter(
        (record) =>
          record.sessionID === sessionID &&
          (request.pointerContextID === null ||
            record.pointerContextID === request.pointerContextID) &&
          (language === null || record.languageReferences.includes(language)),
      );
      return matches.length === 1 ? (matches[0] ?? null) : null;
    },
  };
}

function freezeTarget(record: KnownTarget): KnownTarget {
  const normalizedReferences = record.languageReferences.map(normalizeLanguageReference);
  if (
    !/^room_[a-z0-9_]{3,120}$/u.test(record.sessionID) ||
    !/^object_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(
      record.targetID,
    ) ||
    !/^[A-Za-z][A-Za-z0-9_-]{0,127}$/u.test(record.pointerContextID) ||
    !/^reveal_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(
      record.revealBundleID,
    ) ||
    record.languageReferences.length > 16 ||
    normalizedReferences.some((value) => value === null) ||
    record.worldFromTarget.length !== 16 ||
    !record.worldFromTarget.every(Number.isFinite) ||
    !validDimensions(record.dimensionsM)
  ) {
    throw new TypeError("invalid_known_target");
  }
  return Object.freeze({
    ...record,
    languageReferences: Object.freeze([
      ...new Set(normalizedReferences.filter((value): value is string => value !== null)),
    ]),
    worldFromTarget: Object.freeze([...record.worldFromTarget]),
    dimensionsM: Object.freeze({ ...record.dimensionsM }),
  });
}

function normalizeLanguageReference(value: string | null): string | null {
  if (value === null) return null;
  const normalized = value.trim().toLocaleLowerCase("en-US");
  return normalized.length >= 1 && normalized.length <= 128 && !/[\r\n]/u.test(normalized)
    ? normalized
    : null;
}

function validDimensions(dimensions: KnownTarget["dimensionsM"]): boolean {
  return [dimensions.width, dimensions.height, dimensions.depth].every(
    (value) => Number.isFinite(value) && value > 0 && value < 100,
  );
}
