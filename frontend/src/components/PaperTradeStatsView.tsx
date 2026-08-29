import type { ReactNode } from "react";
import type { PaperStatsData, PaperTrade } from "../types";
import { timeAgo } from "../lib/format";

interface Props {
  data: PaperStatsData | null;
  openTrades: PaperTrade[] | null;
}

export function PaperTradeStatsView({ data, openTrades }: Props) {
  return (
    <>
      <section className="rounded-2xl border border-sky-900/40 bg-gradient-to-br from-sky-950/30 to-zinc-950 p-6">
        <div className="mb-5">
          <div className="mb-1 flex items-center gap-2">
            <span className="text-xl">📊</span>
            <h2 className="text-base font-bold text-white">Paper Trading</h2>
          </div>
          <p className="font-mono text-[10px] uppercase tracking-wider text-zinc-500">
            hypothetical p&amp;l · no real money
          </p>
        </div>

        {data === null ? (
          <p className="text-sm text-red-400">Gagal memuat paper trade stats.</p>
        ) : (
          <>
            <div className="mb-5 grid grid-cols-2 gap-3 md:grid-cols-4">
              <Tile
                label="Win Rate"
                value={`${data.win_rate}%`}
                tone={data.win_rate >= 50 ? "up" : data.win_rate > 0 ? "down" : "neutral"}
                sub={
                  <>
                    <span className="text-emerald-500">{data.winners}W</span>{" "}
                    <span className="text-zinc-700">·</span>{" "}
                    <span className="text-rose-500">{data.losers}L</span>
                  </>
                }
              />
              <Tile
                label="Avg P&L"
                value={`${data.avg_pnl > 0 ? "+" : ""}${data.avg_pnl}%`}
                tone={data.avg_pnl >= 0 ? "up" : "down"}
                sub="per closed trade"
              />
              <Tile label="Open" value={String(data.open_count)} tone="sky" sub="active trades" />
              <Tile label="Closed" value={String(data.total_closed)} sub="total trades" />
            </div>

            <div className="mb-5 grid grid-cols-3 gap-3">
              <Tile
                label="Profit Factor"
                value={data.profit_factor === null ? "—" : String(data.profit_factor)}
                tone={data.profit_factor === null ? "neutral" : data.profit_factor >= 1 ? "up" : "down"}
                sub="gain ÷ loss"
                small
              />
              <Tile
                label="Max Drawdown"
                value={data.max_drawdown === null ? "—" : `-${data.max_drawdown}%`}
                tone={data.max_drawdown === null ? "neutral" : "down"}
                sub="peak-to-trough"
                small
              />
              <Tile
                label="Sharpe"
                value={data.sharpe === null ? "—" : String(data.sharpe)}
                tone={data.sharpe === null ? "neutral" : data.sharpe >= 0 ? "up" : "down"}
                sub="per trade"
                small
              />
            </div>

            {data.by_strategy.length === 0 ? (
              <div className="rounded-xl border border-zinc-900 bg-zinc-950/40 p-8 text-center">
                <div className="mb-2 text-3xl opacity-30">⏳</div>
                <div className="text-sm text-zinc-500">No closed trades yet</div>
                <div className="mt-1 font-mono text-[10px] uppercase tracking-wider text-zinc-700">
                  waiting for first closure...
                </div>
              </div>
            ) : (
              <div className="rounded-xl border border-zinc-900 bg-zinc-950/40 p-4">
                <div className="mb-3 flex items-center justify-between font-mono text-[10px] uppercase tracking-wider text-zinc-500">
                  <span>By Strategy</span>
                  <span className="text-zinc-700">sorted by avg P&L</span>
                </div>
                <div className="space-y-2">
                  {data.by_strategy.map((s) => (
                    <div key={s.strategy} className="flex items-center justify-between rounded px-2 py-1.5 hover:bg-zinc-900/50">
                      <div className="flex min-w-0 flex-1 items-center gap-3">
                        <span className="truncate font-mono text-xs text-zinc-300">{s.strategy}</span>
                        <span className="shrink-0 font-mono text-[10px] text-zinc-600">n={s.total}</span>
                      </div>
                      <div className="flex shrink-0 items-center gap-4">
                        <div className="text-right">
                          <div className="font-mono text-[10px] text-zinc-600">WR</div>
                          <div className={`text-xs font-bold tabular-nums ${s.win_rate >= 50 ? "text-emerald-400" : "text-zinc-400"}`}>
                            {s.win_rate}%
                          </div>
                        </div>
                        <div className="w-20 text-right">
                          <div className="font-mono text-[10px] text-zinc-600">avg</div>
                          <div className={`text-xs font-bold tabular-nums ${s.avg_pnl >= 0 ? "text-emerald-400" : "text-rose-400"}`}>
                            {s.avg_pnl > 0 ? "+" : ""}
                            {s.avg_pnl}%
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </section>

      {openTrades === null ? (
        <p className="text-sm text-red-400">Gagal memuat open trades.</p>
      ) : openTrades.length > 0 ? (
        <section className="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900/50">
          <div className="flex items-center justify-between border-b border-zinc-800 px-5 py-4">
            <div className="flex items-center gap-3">
              <h2 className="text-sm font-bold text-white">Open Positions</h2>
              <span className="rounded-full bg-sky-500/10 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-sky-400">
                {openTrades.length} active
              </span>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-zinc-900 bg-zinc-950/50 text-left text-[10px] uppercase tracking-wider text-zinc-500">
                  <th className="px-5 py-2.5 font-semibold">Symbol</th>
                  <th className="px-5 py-2.5 font-semibold">Side</th>
                  <th className="hidden px-5 py-2.5 font-semibold md:table-cell">Strategy</th>
                  <th className="px-5 py-2.5 text-right font-semibold">Entry</th>
                  <th className="px-5 py-2.5 text-right font-semibold">Current</th>
                  <th className="px-5 py-2.5 text-right font-semibold">P&L</th>
                  <th className="px-5 py-2.5 text-right font-semibold">Age</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-900">
                {openTrades.map((t) => {
                  const pnl = t.current_pnl_pct ?? 0;
                  return (
                    <tr key={t.id} className="transition-colors hover:bg-zinc-900/40">
                      <td className="px-5 py-2.5 font-mono text-xs font-semibold text-white">
                        {t.symbol.replace(".JK", "")}
                      </td>
                      <td className="px-5 py-2.5">
                        <span
                          className={`inline-flex items-center gap-1 rounded px-2 py-0.5 text-[10px] font-bold ${
                            t.side === "BUY" ? "bg-emerald-500/10 text-emerald-400" : "bg-rose-500/10 text-rose-400"
                          }`}
                        >
                          {t.side === "BUY" ? "↑" : "↓"} {t.side}
                        </span>
                      </td>
                      <td className="hidden px-5 py-2.5 font-mono text-[10px] text-zinc-500 md:table-cell">
                        {t.strategy}
                      </td>
                      <td className="px-5 py-2.5 text-right font-mono text-xs tabular-nums text-zinc-400">
                        {t.entry_price}
                      </td>
                      <td className="px-5 py-2.5 text-right font-mono text-xs tabular-nums text-zinc-300">
                        {t.current_price ?? "-"}
                      </td>
                      <td className="px-5 py-2.5 text-right">
                        <span className={`font-mono text-xs font-bold tabular-nums ${pnl >= 0 ? "text-emerald-400" : "text-rose-400"}`}>
                          {pnl >= 0 ? "+" : ""}
                          {pnl.toFixed(2)}%
                        </span>
                      </td>
                      <td className="px-5 py-2.5 text-right font-mono text-[10px] text-zinc-600">
                        {timeAgo(t.entry_at)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}
    </>
  );
}

function Tile({
  label,
  value,
  sub,
  tone = "neutral",
  small = false,
}: {
  label: string;
  value: string;
  sub?: ReactNode;
  tone?: "up" | "down" | "sky" | "neutral";
  small?: boolean;
}) {
  const color = { up: "text-emerald-400", down: "text-rose-400", sky: "text-sky-400", neutral: "text-zinc-300" }[tone];
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4">
      <div className="mb-2 font-mono text-[10px] uppercase tracking-wider text-zinc-500">{label}</div>
      <div className={`font-black tabular-nums ${small ? "text-2xl" : "text-3xl"} ${color}`}>{value}</div>
      {sub && <div className="mt-1 font-mono text-[10px] text-zinc-600">{sub}</div>}
    </div>
  );
}
