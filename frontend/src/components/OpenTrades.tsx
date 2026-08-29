import type { PaperTrade } from "../types";

export function OpenTrades({ trades }: { trades: PaperTrade[] | null }) {
  if (trades === null) return <p className="text-sm text-red-400">Gagal memuat open trades.</p>;
  if (trades.length === 0) return <p className="text-sm text-zinc-500">Tidak ada posisi terbuka.</p>;

  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-zinc-800 text-left text-[10px] uppercase tracking-wider text-zinc-500">
          <th className="pb-2 font-medium">Symbol</th>
          <th className="pb-2 font-medium">Strategy</th>
          <th className="pb-2 font-medium">Entry</th>
          <th className="pb-2 font-medium">Current PnL</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-zinc-900">
        {trades.map((t) => (
          <tr key={t.id} className="text-zinc-300">
            <td className="py-2 font-medium text-sky-400">{t.symbol.replace(".JK", "")}</td>
            <td className="py-2">{t.strategy}</td>
            <td className="py-2">{t.entry_price}</td>
            <td
              className={`py-2 font-medium ${
                (t.current_pnl_pct ?? 0) >= 0 ? "text-emerald-400" : "text-red-400"
              }`}
            >
              {t.current_pnl_pct ?? "-"}%
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
