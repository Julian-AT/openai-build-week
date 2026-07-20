'use client';

import Image from "next/image";
import { useState } from "react";

import { moveTimelineIndex, selectTimelineIndex } from "../lib/replay/timeline.ts";
import type { JsonObject, ReplayEventView, VerifiedReplayView } from "../lib/replay/types.ts";

type ReplayExplorerProps = {
  replay: VerifiedReplayView;
};

function inspectorJson(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

function eventFrameId(event: ReplayEventView): string | null {
  const details = event.payload.details;
  if (details === null || typeof details !== "object" || Array.isArray(details)) return null;
  const candidate = (details as JsonObject).frame_id;
  return typeof candidate === "string" ? candidate : null;
}

function absenceText(value: "not_present"): string {
  return value === "not_present" ? "not present in this capture" : value;
}

export function ReplayExplorer({ replay }: ReplayExplorerProps) {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(() =>
    selectTimelineIndex(replay.events, 0),
  );
  const selectedEvent = selectedIndex === null ? null : replay.events[selectedIndex] ?? null;
  const referencedFrameId = selectedEvent === null ? null : eventFrameId(selectedEvent);
  const selectedFrame =
    (referencedFrameId === null
      ? null
      : replay.frames.find(({ frameId }) => frameId === referencedFrameId))
    ?? replay.frames[0]
    ?? null;

  const selectIndex = (requestedIndex: number) => {
    setSelectedIndex(selectTimelineIndex(replay.events, requestedIndex));
  };
  const moveIndex = (offset: number) => {
    setSelectedIndex((currentIndex) =>
      moveTimelineIndex(replay.events, currentIndex ?? 0, offset),
    );
  };

  return (
    <div className="replay-explorer">
      <section className="status-rail" aria-label="Replay status">
        <div>
          <span className="eyebrow">Verification</span>
          <strong className="status-value status-value--accept">accepted</strong>
        </div>
        <div>
          <span className="eyebrow">Archive</span>
          <strong className="status-value">{replay.archive.finalizationState}</strong>
        </div>
        <div>
          <span className="eyebrow">Events</span>
          <strong className="status-value">{replay.archive.eventCount}</strong>
        </div>
        <div>
          <span className="eyebrow">Frames</span>
          <strong className="status-value">{replay.archive.acceptedFrameCount}</strong>
        </div>
        <div>
          <span className="eyebrow">Provider lock</span>
          <strong className="status-value">{replay.archive.providerLock.length === 0 ? "none" : "present"}</strong>
        </div>
      </section>

      <div className="replay-grid">
        <section className="panel preview-panel" aria-labelledby="preview-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Manifest-bound media</span>
              <h2 id="preview-title">Accepted frame preview</h2>
            </div>
            <span className="signal-chip signal-chip--available">available</span>
          </div>
          {selectedFrame === null ? (
            <p className="empty-state">No accepted frame is present in this verified capture.</p>
          ) : (
            <>
              <div className="frame-stage">
                <Image
                  className="frame-image"
                  src={selectedFrame.preview.dataUrl}
                  alt="Synthetic one-pixel golden capture frame used for the local replay fixture"
                  width={1}
                  height={1}
                  unoptimized
                  priority
                />
                <div className="frame-reticle" aria-hidden="true" />
                <span className="frame-badge">SYNTHETIC 1 × 1 PNG</span>
              </div>
              <dl className="metric-grid">
                <div>
                  <dt>Frame ID</dt>
                  <dd><code>{selectedFrame.frameId}</code></dd>
                </div>
                <div>
                  <dt>Device time</dt>
                  <dd><code>{selectedFrame.monotonicTimestampNs} ns</code></dd>
                </div>
                <div>
                  <dt>Journal</dt>
                  <dd><code>#{selectedFrame.durableJournalSequence}</code></dd>
                </div>
                <div>
                  <dt>Tracking</dt>
                  <dd><code>{String(selectedFrame.tracking.state)}</code></dd>
                </div>
              </dl>
            </>
          )}
        </section>

        <section className="panel timeline-panel" aria-labelledby="timeline-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Global journal order</span>
              <h2 id="timeline-title">Authoritative timeline</h2>
            </div>
            <span className="sequence-readout">
              {selectedIndex === null ? "0 / 0" : `${selectedIndex + 1} / ${replay.events.length}`}
            </span>
          </div>

          {selectedEvent === null || selectedIndex === null ? (
            <p className="empty-state" role="status">
              No verified events are present. Timeline controls are unavailable.
            </p>
          ) : (
            <>
              <div className="timeline-control">
                <label htmlFor="event-scrubber">Verified event index</label>
                <input
                  id="event-scrubber"
                  type="range"
                  min={0}
                  max={replay.events.length - 1}
                  step={1}
                  value={selectedIndex}
                  aria-valuetext={`Event ${selectedIndex + 1} of ${replay.events.length}: ${selectedEvent.type}`}
                  onChange={(event) => selectIndex(Number(event.currentTarget.value))}
                />
                <div className="timeline-actions">
                  <button
                    type="button"
                    onClick={() => moveIndex(-1)}
                    disabled={selectedIndex === 0}
                  >
                    Previous event
                  </button>
                  <button
                    type="button"
                    onClick={() => moveIndex(1)}
                    disabled={selectedIndex === replay.events.length - 1}
                  >
                    Next event
                  </button>
                </div>
              </div>

              <div className="selected-event" aria-live="polite" aria-atomic="true">
                <div className="event-index">EVENT {String(selectedEvent.eventSequence).padStart(2, "0")}</div>
                <h3>{selectedEvent.type}</h3>
                <dl className="inspector-list">
                  <div><dt>Stable ID</dt><dd><code>{selectedEvent.eventId}</code></dd></div>
                  <div><dt>Event sequence</dt><dd><code>{selectedEvent.eventSequence}</code></dd></div>
                  <div><dt>Journal sequence</dt><dd><code>{selectedEvent.durableJournalSequence}</code></dd></div>
                  <div><dt>Monotonic time</dt><dd><code>{selectedEvent.monotonicTimestampNs} ns</code></dd></div>
                </dl>
                <details className="payload-details" open>
                  <summary>Verified event payload</summary>
                  <pre>{inspectorJson(selectedEvent.payload)}</pre>
                </details>
              </div>
            </>
          )}
        </section>

        <section className="panel integrity-panel" aria-labelledby="integrity-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Exact replay proof</span>
              <h2 id="integrity-title">Integrity</h2>
            </div>
            <span className="signal-chip signal-chip--available">verified</span>
          </div>
          <dl className="inspector-list">
            <div><dt>Fixture</dt><dd><code>{replay.verification.fixtureId} / {replay.verification.fixtureRevision}</code></dd></div>
            <div><dt>Archive</dt><dd><code>{replay.archive.archiveName}</code></dd></div>
            <div><dt>Report SHA-256</dt><dd><code>{replay.verification.reportSha256}</code></dd></div>
            <div><dt>Manifest SHA-256</dt><dd><code>{replay.archive.manifestSha256}</code></dd></div>
            <div><dt>Event projection</dt><dd><code>{replay.archive.digests.eventProjectionSha256}</code></dd></div>
            <div><dt>Frame projection</dt><dd><code>{replay.archive.digests.frameProjectionSha256}</code></dd></div>
            <div><dt>Journal tuples</dt><dd><code>{replay.archive.digests.journalTupleSha256}</code></dd></div>
            <div><dt>Revision trace</dt><dd><code>{replay.archive.digests.revisionTraceSha256}</code></dd></div>
          </dl>
        </section>

        <section className="panel privacy-panel" aria-labelledby="privacy-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Manifest state</span>
              <h2 id="privacy-title">Privacy & retention</h2>
            </div>
            <span className="signal-chip">local only</span>
          </div>
          <dl className="inspector-list">
            <div><dt>Capture consent</dt><dd><code>{String(replay.privacy.captureConsentRecorded)}</code></dd></div>
            <div><dt>Room imagery</dt><dd><code>{String(replay.privacy.containsRoomImagery)}</code></dd></div>
            <div><dt>Retention policy</dt><dd><code>{replay.privacy.retentionPolicy}</code></dd></div>
            <div><dt>Share access</dt><dd><code>{replay.privacy.shareAccessState}</code></dd></div>
            <div><dt>Deletion state</dt><dd><code>{replay.privacy.deletionState}</code></dd></div>
            <div><dt>Browser persistence</dt><dd><code>{replay.privacy.browserPersistence}</code></dd></div>
          </dl>
          <p className="panel-note">
            Closing this tab discards the selected timeline position. No browser or server session is created.
          </p>
        </section>

        <section className="panel absence-panel" aria-labelledby="absence-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Capture contents</span>
              <h2 id="absence-title">Scene & transactions</h2>
            </div>
          </div>
          <dl className="absence-grid">
            <div>
              <dt>Scene</dt>
              <dd>{absenceText(replay.content.scene)}</dd>
            </div>
            <div>
              <dt>Transactions</dt>
              <dd>{absenceText(replay.content.transactions)}</dd>
            </div>
          </dl>
          <p className="panel-note">No geometry, edit history, or provider output is inferred from lifecycle events.</p>
        </section>

        <section className="panel capability-panel" aria-labelledby="capability-title">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">Honest degradation</span>
              <h2 id="capability-title">Capability ledger</h2>
            </div>
          </div>
          <ul className="capability-list">
            {replay.capabilities.map((capability) => (
              <li key={capability.id}>
                <div>
                  <strong>{capability.label}</strong>
                  <p>{capability.detail}</p>
                </div>
                <span className={`signal-chip signal-chip--${capability.state}`}>
                  {capability.state.replace("_", " ")}
                </span>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
