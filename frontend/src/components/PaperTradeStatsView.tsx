import type { PaperStatsData } from "../types";

export function PaperTradeStatsView({ data }: { data: PaperStatsData | null }) {
  if (data === null) return <p>Gagal memuat paper trade stats.</p>;
  if (data.by_strategy.length === 0) {
    return <p>Belum ada breakdown strategi.</p>;
  }

  return (
    <div>
      <p>
        Closed: {data.total_closed} · Open: {data.open_count} · Win rate:{" "}
        {data.win_rate.toFixed(1)}%
      </p>
      <p>
        Avg PnL: {data.avg_pnl.toFixed(2)}% · Expectancy: {data.expectancy.toFixed(2)}% ·
        Profit factor: {data.profit_factor ?? "-"} · Sharpe: {data.sharpe ?? "-"}
      </p>
      {data.best_trade && (
        <p>
          Best: {data.best_trade.symbol.replace(".JK", "")} (
          {data.best_trade.pnl_pct.toFixed(2)}%)
        </p>
      )}
      {data.worst_trade && (
        <p>
          Worst: {data.worst_trade.symbol.replace(".JK", "")} (
          {data.worst_trade.pnl_pct.toFixed(2)}%)
        </p>
      )}
      <table>
        <thead>
          <tr>
            <th>Strategy</th>
            <th>Total</th>
            <th>Win rate</th>
            <th>Avg PnL</th>
          </tr>
        </thead>
        <tbody>
          {data.by_strategy.map((s) => (
            <tr key={s.strategy}>
              <td>{s.strategy}</td>
              <td>{s.total}</td>
              <td>{s.win_rate.toFixed(1)}%</td>
              <td>{s.avg_pnl.toFixed(2)}%</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
