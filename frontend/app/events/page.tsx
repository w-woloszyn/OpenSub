"use client";

function EventsContent() {
  return (
    <div className="card">
      <h2 style={{ marginTop: 0 }}>Events</h2>
      <p className="muted" style={{ marginTop: 6 }}>
        The Events UI is disabled in this demo.
      </p>
    </div>
  );
}

export default function EventsPage() {
  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <EventsContent />
    </main>
  );
}
