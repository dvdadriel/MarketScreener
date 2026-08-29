import type { Signal } from "../types";
import { idr } from "../lib/format";

export function SwingPicks({ picks }: { picks: Signal[] | null }) {
  if (picks === null) return <p className="text-sm text-red-400">Gagal memuat swing picks.</p>;
  if (picks.length === 0)
    return <p className="font-mono text-xs text-zinc-500">Tidak ada swing pick baru 24 jam terakhir.</p>;

  return (
    <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
      {picks.map((p) => {
        const meta = (p.metadata ?? {}) as Record<string, number | boolean | undefined>;
        const scorePct = p.score !== null ? Math.round(p.score * 100) : 0;
        const priceVsMa50 = Number(meta.price_vs_ma50 ?? 0);

        return (
          <div key={p.id} className="rounded-xl border border-sky-900/30 bg-zinc-950/60 p-4">
            <div className="mb-3 flex items-start justify-between">
              <div className="flex items-center gap-3">
                <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-to-br from-sky-500 to-blue-600 text-sm font-bold text-white">
                  {String(meta.rank ?? "-")}
                </div>
                <div>
                  <div className="font-mono text-base font-bold text-white">{p.symbol.replace(".JK", "")}</div>
                  <div className="text-[10px] text-zinc-500">Rp {idr(Number(meta.last_close ?? 0))}</div>
                </div>
              </div>
              <div className="rounded-full bg-sky-500/20 px-2.5 py-1 text-xs font-bold text-sky-300">{scorePct}%</div>
            </div>

            <div className="flex flex-wrap items-center gap-2 text-[10px]">
              <span className="rounded bg-zinc-900 px-1.5 py-0.5 font-mono text-zinc-400">
                RSI <span className="text-white">{String(meta.rsi ?? "-")}</span>
              </span>
              <span className="rounded bg-zinc-900 px-1.5 py-0.5 font-mono text-zinc-400">
                MACD{" "}
                <span className="text-white">
                  {typeof meta.macd_hist === "number" ? meta.macd_hist.toFixed(2) : "-"}
                  {meta.macd_rising ? " ↑" : ""}
                </span>
              </span>
              <span className="rounded bg-zinc-900 px-1.5 py-0.5 font-mono text-zinc-400">
                Vol <span className="text-white">{String(meta.volume_ratio ?? "-")}x</span>
              </span>
              <span
                className={`rounded px-1.5 py-0.5 font-mono ${
                  priceVsMa50 >= 0 ? "bg-emerald-950 text-emerald-300" : "bg-rose-950 text-rose-300"
                }`}
              >
                MA50 {priceVsMa50 >= 0 ? "+" : ""}
                {priceVsMa50}%
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
