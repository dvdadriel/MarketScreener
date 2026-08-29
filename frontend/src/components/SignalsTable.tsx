import type { LatestClose, Signal } from "../types";

interface Props {
  signals: Signal[] | null;
  closes: LatestClose[] | null;
}

export function SignalsTable({ signals, closes }: Props) {
  if (signals === null) return <p className="text-sm text-red-400">Gagal memuat signals.</p>;
  if (signals.length === 0) return <p className="text-sm text-zinc-500">Belum ada signal.</p>;

  const closeBySymbol = new Map((closes ?? []).map((c) => [c.symbol, c.close]));

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-zinc-800 text-left text-[10px] uppercase tracking-wider text-zinc-500">
            <th className="pb-2 font-medium">Symbol</th>
            <th className="pb-2 font-medium">Strategy</th>
            <th className="pb-2 font-medium">Type</th>
            <th className="pb-2 font-medium">Score</th>
            <th className="pb-2 font-medium">Last close</th>
            <th className="pb-2 font-medium">Fired at</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-900">
          {signals.map((s) => (
            <tr key={s.id} className="text-zinc-300">
              <td className="py-2 font-medium text-sky-400">{s.symbol.replace(".JK", "")}</td>
              <td className="py-2">{s.strategy}</td>
              <td className="py-2">{s.signal_type ?? "-"}</td>
              <td className="py-2">{s.score ?? "-"}</td>
              <td className="py-2">{closeBySymbol.get(s.symbol) ?? "-"}</td>
              <td className="py-2 text-zinc-500">
                {new Date(s.fired_at).toLocaleString("id-ID")}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
