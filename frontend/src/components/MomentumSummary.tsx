import type { MomentumSummaryData } from "../types";

export function MomentumSummary({ data }: { data: MomentumSummaryData | null }) {
  if (data === null) return <p className="text-sm text-red-400">Gagal memuat forward tracking.</p>;
  if (data.tracked_days === 0) {
    return <p className="text-sm text-zinc-500">Belum ada snapshot momentum.</p>;
  }

  const alpha =
    data.ihsg_return !== null ? (data.total_return - data.ihsg_return).toFixed(2) : "-";
  const riskOn = data.regime_today === "risk_on";

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-zinc-500">
          {data.inception} → {data.as_of} · {data.tracked_days} hari-snapshot
        </p>
        <span
          className={`rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider ${
            riskOn ? "bg-emerald-500/20 text-emerald-300" : "bg-red-500/20 text-red-300"
          }`}
        >
          {data.regime_today ?? "-"}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Equity" value={data.equity.toFixed(2)} />
        <Stat
          label="Return"
          value={`${data.total_return >= 0 ? "+" : ""}${data.total_return.toFixed(2)}%`}
          tone={data.total_return >= 0 ? "up" : "down"}
        />
        <Stat label="Max DD" value={`-${data.max_drawdown.toFixed(2)}%`} tone="down" />
        <Stat label="Alpha vs IHSG" value={`${alpha}%`} tone={Number(alpha) >= 0 ? "up" : "down"} />
      </div>

      <p className="text-xs text-zinc-500">
        Holdings: <span className="text-zinc-300">{data.holdings.length ? data.holdings.join(", ") : "CASH"}</span>
      </p>
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
