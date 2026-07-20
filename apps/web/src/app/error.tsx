"use client";

export default function ReplayError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="app-shell app-shell--error">
      <header className="product-header">
        <div className="brand-lockup">
          <span className="brand-mark" aria-hidden="true">
            RF
          </span>
          <div>
            <span className="brand-name">Reframe</span>
            <span className="brand-subtitle">Session replay</span>
          </div>
        </div>
        <div className="mode-lockup">
          <p className="mode-title">MODE B0 — RECORDED REPLAY</p>
          <div className="mode-badges">
            <span>SAFE FAILURE</span>
            <span>SESSION ISOLATED</span>
            <span className="mode-badge--pending">RETRY AVAILABLE</span>
          </div>
        </div>
      </header>
      <section className="closed-state" aria-labelledby="render-failed-title">
        <div className="closed-state__icon" aria-hidden="true">
          !
        </div>
        <span className="eyebrow">Closed error surface</span>
        <h1 id="render-failed-title">Replay view unavailable</h1>
        <p>
          The recorded replay could not be rendered safely. No timeline, frame, manifest, or
          inspector data is shown.
        </p>
        <button type="button" onClick={reset}>
          Try the verified replay again
        </button>
      </section>
    </main>
  );
}
