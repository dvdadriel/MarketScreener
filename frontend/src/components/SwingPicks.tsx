import type { Signal } from "../types";

export function SwingPicks({ picks }: { picks: Signal[] | null }) {
  if (picks === null) return <p className="text-sm text-red-400">Gagal memuat swing picks.</p>;
  if (picks.length === 0)
    return <p className="text-sm text-zinc-500">Tidak ada swing pick baru 24 jam terakhir.</p>;

  return (
    <ul className="flex flex-wrap gap-2">
      {picks.map((p) => (
        <li
          key={p.id}
          className="rounded-lg bg-zinc-900/60 px-3 py-1.5 text-sm text-zinc-200"
        >
          <span className="font-semibold text-sky-400">{p.symbol.replace(".JK", "")}</span>{" "}
          <span className="text-zinc-500">rank {String(p.metadata?.rank ?? "-")}</span>
        </li>
      ))}
    </ul>
  );
}
