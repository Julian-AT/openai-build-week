export function selectTimelineIndex(
  events: readonly unknown[],
  requestedIndex: number,
): number | null {
  if (events.length === 0) return null;
  const normalized = Number.isFinite(requestedIndex) ? Math.trunc(requestedIndex) : 0;
  return Math.min(events.length - 1, Math.max(0, normalized));
}

export function moveTimelineIndex(
  events: readonly unknown[],
  currentIndex: number,
  offset: number,
): number | null {
  const selected = selectTimelineIndex(events, currentIndex);
  if (selected === null) return null;
  if (!Number.isFinite(offset)) return selected;
  return selectTimelineIndex(events, selected + Math.trunc(offset));
}
