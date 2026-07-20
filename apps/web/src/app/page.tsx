import { ReplayExplorer } from "../components/replay-explorer";
import { loadGoldenCapture } from "../lib/replay/load-golden-capture.server.ts";

export const dynamic = "force-dynamic";

function ProductHeader() {
  return (
    <header className="product-header">
      <div className="brand-lockup" aria-label="ReRoom recorded replay">
        <span className="brand-mark" aria-hidden="true">RR</span>
        <div>
          <span className="brand-name">ReRoom</span>
          <span className="brand-subtitle">Fallback inspection console</span>
        </div>
      </div>
      <div className="mode-lockup">
        <p className="mode-title">MODE B0 — RECORDED REPLAY</p>
        <div className="mode-badges" aria-label="Mode constraints">
          <span>PROVIDER-INDEPENDENT</span>
          <span>LOCAL DEMO FIXTURE</span>
          <span className="mode-badge--pending">GATE-008 PENDING</span>
        </div>
      </div>
    </header>
  );
}

function VerificationFailure() {
  return (
    <section className="closed-state" aria-labelledby="verification-failed-title">
      <div className="closed-state__icon" aria-hidden="true">!</div>
      <span className="eyebrow">Fail-closed boundary</span>
      <h1 id="verification-failed-title">Archive verification failed</h1>
      <p>
        The local replay fixture could not be verified. Timeline, frame, manifest, and inspector data remain hidden.
      </p>
      <p className="closed-state__note">
        No partial capture data is trusted or rendered. GATE-008 remains pending.
      </p>
    </section>
  );
}

export default async function HomePage() {
  const result = await loadGoldenCapture();

  return (
    <main className="app-shell">
      <ProductHeader />
      {result.status === "verified" ? (
        <>
          <section className="intro-copy" aria-labelledby="replay-heading">
            <div>
              <span className="eyebrow">Automated evidence</span>
              <h1 id="replay-heading">Verified capture, inspection-only controls.</h1>
            </div>
            <p>
              The exact Phase 2 runner accepted this fixed capture. That acceptance does not close the full
              GATE-008 browser, ordinary-video, retention, or fault-evidence matrix.
            </p>
          </section>
          <ReplayExplorer replay={result.replay} />
          <footer className="page-footer">
            <p>Local fixture · in-memory selection · no upload · no provider · no account · no cloud</p>
            <p>Closing this tab discards UI selection. The repository fixture is unchanged.</p>
          </footer>
        </>
      ) : (
        <VerificationFailure />
      )}
    </main>
  );
}
