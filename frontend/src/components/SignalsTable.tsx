import type { LatestClose, Signal } from "../types";
import { timeAgo } from "../lib/format";

interface Props {
  signals: Signal[] | null;
  closes: LatestClose[] | null;
}

export function SignalsTable({ signals, closes }: Props) {
  const closeBySymbol = new Map((closes ?? []).map((c) => [c.symbol, c.close]));

  return (
    <section className="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900/50">
      <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-4">
        <div className="flex items-center gap-3">
          <h2 className="text-sm font-bold text-white">🇮🇩 IDX Signals</h2>
          <span className="rounded-full bg-zinc-800 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-zinc-400">
            {signals?.length ?? 0} recent
          </span>
        </div>
        <div className="flex items-center gap-1.5 text-[10px] text-zinc-500">
          <span className="relative flex h-1.5 w-1.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
            <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500" />
          </span>
          <span className="font-mono uppercase tracking-wider">live updates</span>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-zinc-800 bg-zinc-950/50 text-left text-[10px] uppercase tracking-wider text-zinc-500">
              <th className="px-5 py-2.5 font-semibold">Symbol</th>
              <th className="px-5 py-2.5 font-semibold">Strategy</th>
              <th className="px-5 py-2.5 font-semibold">Side</th>
              <th className="px-5 py-2.5 font-semibold">Score</th>
              <th className="px-5 py-2.5 font-semibold">Last close</th>
              <th className="px-5 py-2.5 text-right font-semibold">Fired</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-900">
            {signals === null ? (
              <tr>
                <td colSpan={6} className="px-5 py-16 text-center text-sm text-red-400">
                  Gagal memuat signals.
                </td>
              </tr>
            ) : signals.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-5 py-16 text-center">
                  <div className="flex flex-col items-center gap-2">
                    <div className="flex h-12 w-12 items-center justify-center rounded-full bg-zinc-900 text-2xl opacity-50">
                      📡
                    </div>
                    <div className="text-sm text-zinc-500">No signals yet</div>
                    <div className="font-mono text-[10px] uppercase tracking-wider text-zinc-700">
                      waiting for confluence...
                    </div>
                  </div>
                </td>
              </tr>
            ) : (
              signals.map((s) => {
                const isBuy = s.signal_type === "BUY";
                const scorePct = s.score !== null ? Math.round(s.score * 100) : 0;

                return (
                  <tr key={s.id} className="group transition-colors hover:bg-zinc-900/50">
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-2.5">
                        <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br from-sky-600 to-blue-700 text-[10px] font-bold text-white">
                          JK
                        </div>
                        <div className="font-mono text-sm font-semibold text-white">
                          {s.symbol.replace(".JK", "")}
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-3 font-mono text-xs text-zinc-400">{s.strategy}</td>
                    <td className="px-5 py-3">
                      <span
                        className={`inline-flex items-center gap-1 rounded-lg border px-2.5 py-1 text-[10px] font-bold tracking-wider ${
                          isBuy
                            ? "border-emerald-500/20 bg-emerald-500/10 text-emerald-400"
                            : "border-rose-500/20 bg-rose-500/10 text-rose-400"
                        }`}
                      >
                        {isBuy ? "↑" : "↓"} {s.signal_type ?? "-"}
                      </span>
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-2">
                        <div className="h-1 w-20 overflow-hidden rounded-full bg-zinc-900">
                          <div
                            className={`h-full rounded-full bg-gradient-to-r ${
                              isBuy ? "from-emerald-600 to-emerald-400" : "from-rose-600 to-rose-400"
                            }`}
                            style={{ width: `${scorePct}%` }}
                          />
                        </div>
                        <span className={`font-mono text-xs font-bold tabular-nums ${isBuy ? "text-emerald-400" : "text-rose-400"}`}>
                          {scorePct}%
                        </span>
                      </div>
                    </td>
                    <td className="px-5 py-3 font-mono text-xs text-zinc-300">
                      {closeBySymbol.get(s.symbol) ?? "-"}
                    </td>
                    <td className="px-5 py-3 text-right">
                      <div className="font-mono text-[11px] text-zinc-500">{timeAgo(s.fired_at)}</div>
                      <div className="font-mono text-[10px] text-zinc-700">
                        {new Date(s.fired_at).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })}
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
