import type { PaperStatsData } from "../types";

export function PaperTradeStatsView({ data }: { data: PaperStatsData | null }) {
  if (data === null) return <p className="text-sm text-red-400">Gagal memuat paper trade stats.</p>;
  if (data.by_strategy.length === 0) {
    return <p className="text-sm text-zinc-500">Belum ada breakdown strategi.</p>;
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Closed" value={String(data.total_closed)} />
        <Stat label="Open" value={String(data.open_count)} />
        <Stat label="Win rate" value={`${data.win_rate.toFixed(1)}%`} />
        <Stat
          label="Avg PnL"
          value={`${data.avg_pnl.toFixed(2)}%`}
          tone={data.avg_pnl >= 0 ? "up" : "down"}
        />
      </div>

      <p className="text-xs text-zinc-500">
        Expectancy: <span className="text-zinc-300">{data.expectancy.toFixed(2)}%</span> · Profit
        factor: <span className="text-zinc-300">{data.profit_factor ?? "-"}</span> · Sharpe:{" "}
        <span className="text-zinc-300">{data.sharpe ?? "-"}</span>
      </p>

      <div className="flex flex-wrap gap-3 text-xs">
        {data.best_trade && (
          <span className="rounded-lg bg-emerald-500/10 px-2.5 py-1 text-emerald-300">
            Best: {data.best_trade.symbol.replace(".JK", "")} (+{data.best_trade.pnl_pct.toFixed(2)}%)
          </span>
        )}
        {data.worst_trade && (
          <span className="rounded-lg bg-red-500/10 px-2.5 py-1 text-red-300">
            Worst: {data.worst_trade.symbol.replace(".JK", "")} ({data.worst_trade.pnl_pct.toFixed(2)}%)
          </span>
        )}
      </div>

      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-zinc-800 text-left text-[10px] uppercase tracking-wider text-zinc-500">
            <th className="pb-2 font-medium">Strategy</th>
            <th className="pb-2 font-medium">Total</th>
            <th className="pb-2 font-medium">Win rate</th>
            <th className="pb-2 font-medium">Avg PnL</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-900">
          {data.by_strategy.map((s) => (
            <tr key={s.strategy} className="text-zinc-300">
              <td className="py-2">{s.strategy}</td>
              <td className="py-2">{s.total}</td>
              <td className="py-2">{s.win_rate.toFixed(1)}%</td>
              <td className="py-2">{s.avg_pnl.toFixed(2)}%</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "up" | "down" }) {
  const color = tone === "up" ? "text-emerald-400" : tone === "down" ? "text-red-400" : "text-white";
  return (
    <div className="rounded-xl bg-zinc-900/60 p-3">
      <div className="text-[10px] uppercase tracking-wider text-zinc-500">{label}</div>
      <div className={`text-lg font-bold ${color}`}>{value}</div>
    </div>
  );
}
