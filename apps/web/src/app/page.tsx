const capabilities = [
  ["Capture", "Native spatial understanding on iPhone"],
  ["Design", "Realtime voice and visual collaboration"],
  ["Preview", "Reversible edits before every commit"],
];

export default function HomePage() {
  return (
    <main className="shell">
      <nav className="navigation" aria-label="Primary navigation">
        <a className="wordmark" href="/" aria-label="Reframe home">
          Reframe
        </a>
        <span className="status">System ready</span>
      </nav>

      <section className="hero" aria-labelledby="hero-title">
        <p className="eyebrow">Spatial design intelligence</p>
        <h1 id="hero-title">See your space differently.</h1>
        <p className="lede">
          Reframe understands a real room, finds objects that belong in it, and lets you shape the
          result through a live conversation.
        </p>
        <div className="actions">
          <a className="primary-action" href="#capabilities">
            Explore the system
          </a>
          <span>iPhone capture · browser collaboration</span>
        </div>
      </section>

      <section className="capabilities" id="capabilities" aria-label="Core capabilities">
        {capabilities.map(([title, description], index) => (
          <article key={title}>
            <span className="capability-number">0{index + 1}</span>
            <h2>{title}</h2>
            <p>{description}</p>
          </article>
        ))}
      </section>
    </main>
  );
}
