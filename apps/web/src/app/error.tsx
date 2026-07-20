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
            RR
          </span>
          <div>
            <span className="brand-name">ReRoom</span>
            <span className="brand-subtitle">Fallback inspection console</span>
          </div>
        </div>
        <div className="mode-lockup">
          <p className="mode-title">MODE B0 — RECORDED REPLAY</p>
          <div className="mode-badges">
            <span>PROVIDER-INDEPENDENT</span>
            <span>LOCAL DEMO FIXTURE</span>
            <span className="mode-badge--pending">GATE-008 PENDING</span>
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
