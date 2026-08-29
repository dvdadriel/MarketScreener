import type { Signal } from "../types";

export function SwingPicks({ picks }: { picks: Signal[] | null }) {
  if (picks === null) return <p>Gagal memuat swing picks.</p>;
  if (picks.length === 0) return <p>Tidak ada swing pick baru 24 jam terakhir.</p>;

  return (
    <ul>
      {picks.map((p) => (
        <li key={p.id}>
          {p.symbol.replace(".JK", "")} — rank {String(p.metadata?.rank ?? "-")}
        </li>
      ))}
    </ul>
  );
}
