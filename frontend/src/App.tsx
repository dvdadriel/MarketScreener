import { useEffect, useState } from "react";
import { supabase } from "./lib/supabase";
import { isIdxOpenNow } from "./lib/idxMarket";
import { SignalsTable } from "./components/SignalsTable";
import { SwingPicks } from "./components/SwingPicks";
import { MomentumSummary } from "./components/MomentumSummary";
import { PaperTradeStatsView } from "./components/PaperTradeStatsView";
import type {
  Signal,
  PaperTrade,
  LatestClose,
  MomentumSummaryData,
  PaperStatsData,
} from "./types";

interface DashboardState {
  signals: Signal[] | null;
  closes: LatestClose[] | null;
  swingPicks: Signal[] | null;
  momentum: MomentumSummaryData | null;
  paperStats: PaperStatsData | null;
  openTrades: PaperTrade[] | null;
}

const EMPTY_STATE: DashboardState = {
  signals: null,
  closes: null,
  swingPicks: null,
  momentum: null,
  paperStats: null,
  openTrades: null,
};

export function App() {
  const [state, setState] = useState<DashboardState>(EMPTY_STATE);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const since24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

      try {
        const [signalsRes, closesRes, swingRes, momentumRes, statsRes, tradesRes] =
          await Promise.all([
            supabase
              .from("signals")
              .select("*")
              .eq("asset_type", "stock")
              .order("fired_at", { ascending: false })
              .limit(50),
            supabase
              .from("latest_candle_closes")
              .select("*")
              .eq("asset_type", "stock")
              .eq("timeframe", "1d"),
            supabase
              .from("signals")
              .select("*")
              .eq("strategy", "SWING_PICK")
              .eq("asset_type", "stock")
              .gte("fired_at", since24h)
              .order("fired_at", { ascending: false })
              .limit(10),
            supabase.from("momentum_tracker_summaries").select("data").maybeSingle(),
            supabase
              .from("paper_trade_stats_summaries")
              .select("data")
              .eq("asset_type", "stock")
              .maybeSingle(),
            supabase
              .from("paper_trades")
              .select("*")
              .eq("asset_type", "stock")
              .eq("status", "open")
              .order("entry_at", { ascending: false })
              .limit(20),
          ]);

        setState({
          signals: signalsRes.error ? null : (signalsRes.data as Signal[]),
          closes: closesRes.error ? null : (closesRes.data as LatestClose[]),
          swingPicks: swingRes.error ? null : (swingRes.data as Signal[]),
          momentum: momentumRes.error
            ? null
            : ((momentumRes.data?.data as MomentumSummaryData) ?? null),
          paperStats: statsRes.error
            ? null
            : ((statsRes.data?.data as PaperStatsData) ?? null),
          openTrades: tradesRes.error ? null : (tradesRes.data as PaperTrade[]),
        });
      } catch {
        setState(EMPTY_STATE);
      } finally {
        setLoading(false);
      }
    }

    load();
  }, []);

  const idxOpen = isIdxOpenNow();
  const stocksScanned = state.closes?.length ?? 0;

  return (
    <div className="min-h-screen bg-zinc-950">
      <header className="sticky top-0 z-50 border-b border-zinc-900 bg-zinc-950/80 backdrop-blur-xl">
        <div className="mx-auto flex max-w-[1600px] items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-emerald-500 to-sky-500 text-lg font-black text-white shadow-lg shadow-emerald-500/20">
              ⚡
            </div>
            <div>
              <div className="text-base font-bold tracking-tight text-white">IdxScreener</div>
              <div className="flex items-center gap-1.5 text-[10px]">
                <span className="relative flex h-1.5 w-1.5">
                  <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
                  <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500" />
                </span>
                <span className="font-mono uppercase tracking-wider text-emerald-400">live</span>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[1600px] space-y-6 px-6 py-8">
        {loading ? (
          <p className="text-sm text-zinc-500">Memuat...</p>
        ) : (
          <>
            {/* ===== HERO ===== */}
            <div className="grid grid-cols-1 gap-3">
              <div className="group relative overflow-hidden rounded-2xl border border-zinc-800 bg-gradient-to-br from-zinc-900 to-zinc-950 p-5 text-left">
                <div className="absolute right-0 top-0 h-32 w-32 rounded-full bg-sky-500/5 blur-3xl" />
                <div className="relative">
                  <div className="mb-1 flex items-center gap-2">
                    <span className="text-2xl">🇮🇩</span>
                    <span className="text-xs font-semibold uppercase tracking-wider text-sky-400">
                      IDX Stocks
                    </span>
                    <span
                      className={`ml-auto rounded-full px-2 py-0.5 text-[10px] font-bold ${
                        idxOpen ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-800 text-zinc-400"
                      }`}
                    >
                      {idxOpen ? "● OPEN" : "● CLOSED"}
                    </span>
                  </div>
                  <div className="text-2xl font-bold text-white">
                    {stocksScanned} <span className="text-sm font-normal text-zinc-500">stocks scanned</span>
                  </div>
                  <div className="mt-1 text-xs text-zinc-500">
                    {state.signals?.length ?? 0} signals · {state.openTrades?.length ?? 0} open trades
                  </div>
                </div>
              </div>
            </div>

            {/* ===== MOMENTUM ===== */}
            <section className="rounded-2xl border border-violet-900/40 bg-gradient-to-br from-violet-950/30 to-zinc-950 p-6">
              <div className="mb-3 flex items-center gap-2">
                <span className="text-xl">🚀</span>
                <h2 className="text-base font-bold text-white">Momentum</h2>
                <span className="rounded-full bg-violet-500/10 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-violet-300">
                  observasi · paper
                </span>
              </div>
              <MomentumSummary data={state.momentum} />
            </section>

            {/* ===== SWING PICKS ===== */}
            <section className="rounded-2xl border border-sky-900/40 bg-gradient-to-br from-sky-950/30 to-zinc-950 p-6">
              <div className="mb-5 flex items-center gap-2">
                <span className="text-2xl">📈</span>
                <h2 className="text-lg font-bold text-white">Today's Swing Picks</h2>
              </div>
              <SwingPicks picks={state.swingPicks} />
            </section>

            {/* ===== PAPER TRADING + OPEN POSITIONS ===== */}
            <PaperTradeStatsView data={state.paperStats} openTrades={state.openTrades} />

            {/* ===== SIGNALS TABLE ===== */}
            <SignalsTable signals={state.signals} closes={state.closes} />
          </>
        )}
      </main>

      <footer className="mx-auto max-w-[1600px] px-6 py-8 text-center font-mono text-[10px] uppercase tracking-wider text-zinc-700">
        idxscreener · paper trading mode · no financial advice
      </footer>
    </div>
  );
}
