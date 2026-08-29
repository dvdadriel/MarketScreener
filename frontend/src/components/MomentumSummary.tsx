import type { MomentumSummaryData } from "../types";

export function MomentumSummary({ data }: { data: MomentumSummaryData | null }) {
  if (data === null) return <p className="text-sm text-red-400">Gagal memuat forward tracking.</p>;
  if (data.tracked_days === 0) {
    return <p className="text-sm text-zinc-500">Belum ada snapshot momentum.</p>;
  }

  const alpha = data.ihsg_return !== null ? Number((data.total_return - data.ihsg_return).toFixed(2)) : null;
  const riskOn = data.regime_today === "risk_on";

  return (
    <div>
      <div className="mb-3 flex items-center justify-between gap-2">
        <span
          className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider ${
            riskOn ? "bg-emerald-500/20 text-emerald-300" : "bg-rose-500/20 text-rose-300"
          }`}
        >
          {data.regime_today?.replace("_", "-") ?? "-"}
        </span>
        <div className="font-mono text-[10px] text-zinc-500">
          {data.inception} → {data.as_of} · {data.tracked_days}h
        </div>
      </div>

      <div className="mb-3 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
        <div>
          Paper:{" "}
          <span className={`font-bold tabular-nums ${data.total_return >= 0 ? "text-emerald-400" : "text-rose-400"}`}>
            {data.total_return >= 0 ? "+" : ""}
            {data.total_return}%
          </span>
        </div>
        <div>
          IHSG:{" "}
          <span className="font-bold tabular-nums text-zinc-300">
            {data.ihsg_return !== null ? `${data.ihsg_return >= 0 ? "+" : ""}${data.ihsg_return}%` : "-"}
          </span>
        </div>
        <div>
          Alpha:{" "}
          <span className={`font-bold tabular-nums ${alpha !== null && alpha >= 0 ? "text-emerald-400" : "text-rose-400"}`}>
            {alpha !== null ? `${alpha >= 0 ? "+" : ""}${alpha}%` : "-"}
          </span>
        </div>
        <div className="text-xs text-zinc-500">maxDD -{data.max_drawdown}%</div>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {data.holdings.length ? (
          data.holdings.map((symbol) => (
            <span key={symbol} className="rounded border border-zinc-800 bg-zinc-900 px-2 py-0.5 font-mono text-xs text-zinc-300">
              {symbol.replace(".JK", "")}
            </span>
          ))
        ) : (
          <span className="font-mono text-xs text-zinc-500">CASH — regime risk-off, tidak pegang posisi</span>
        )}
      </div>
    </div>
  );
}
