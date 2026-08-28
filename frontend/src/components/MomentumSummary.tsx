import type { MomentumSummaryData } from "../types";

export function MomentumSummary({ data }: { data: MomentumSummaryData | null }) {
  if (data === null) return <p>Gagal memuat forward tracking.</p>;
  if (data.tracked_days === 0) {
    return <p>Belum ada snapshot momentum.</p>;
  }

  const alpha =
    data.ihsg_return !== null ? (data.total_return - data.ihsg_return).toFixed(2) : "-";

  return (
    <div>
      <p>
        {data.inception} → {data.as_of} ({data.tracked_days} hari-snapshot)
      </p>
      <p>
        Equity: {data.equity.toFixed(2)} ({data.total_return >= 0 ? "+" : ""}
        {data.total_return.toFixed(2)}%) · maxDD: -{data.max_drawdown.toFixed(2)}%
      </p>
      <p>
        IHSG: {data.ihsg_return ?? "-"}% · Alpha: {alpha}% · Regime: {data.regime_today ?? "-"}
      </p>
      <p>Holdings: {data.holdings.length ? data.holdings.join(", ") : "CASH"}</p>
    </div>
  );
}
