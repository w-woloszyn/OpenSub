"use client";

import { GaslessContent } from "@/app/gasless/GaslessContent";

export default function GaslessPage() {
  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <GaslessContent />
    </main>
  );
}
