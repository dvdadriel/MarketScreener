import type { PaperTrade } from "../types";

export function OpenTrades({ trades }: { trades: PaperTrade[] | null }) {
  if (trades === null) return <p>Gagal memuat open trades.</p>;
  if (trades.length === 0) return <p>Tidak ada posisi terbuka.</p>;

  return (
    <table>
      <thead>
        <tr>
          <th>Symbol</th>
          <th>Strategy</th>
          <th>Entry</th>
          <th>Current PnL</th>
        </tr>
      </thead>
      <tbody>
        {trades.map((t) => (
          <tr key={t.id}>
            <td>{t.symbol.replace(".JK", "")}</td>
            <td>{t.strategy}</td>
            <td>{t.entry_price}</td>
            <td>{t.current_pnl_pct ?? "-"}%</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
