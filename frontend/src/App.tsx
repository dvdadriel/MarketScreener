import { useEffect, useState } from "react";
import { supabase } from "./lib/supabase";
import { isIdxOpenNow } from "./lib/idxMarket";
import { SignalsTable } from "./components/SignalsTable";
import { SwingPicks } from "./components/SwingPicks";
import { MomentumSummary } from "./components/MomentumSummary";
import { PaperTradeStatsView } from "./components/PaperTradeStatsView";
import { OpenTrades } from "./components/OpenTrades";
import { Card } from "./components/Card";
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

  return (
    <div className="min-h-screen bg-zinc-950">
      <header className="sticky top-0 z-50 border-b border-zinc-900 bg-zinc-950/80 backdrop-blur-xl">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
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

          <span
            className={`rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider ${
              idxOpen ? "bg-emerald-500/20 text-emerald-300" : "bg-zinc-800 text-zinc-300"
            }`}
          >
            ● IDX {idxOpen ? "OPEN" : "CLOSED"}
          </span>
        </div>
      </header>

      <main className="mx-auto max-w-5xl space-y-6 px-6 py-8">
        {loading ? (
          <p className="text-sm text-zinc-500">Memuat...</p>
        ) : (
          <>
            <Card title="Forward tracking (momentum)" icon="📈">
              <MomentumSummary data={state.momentum} />
            </Card>

            <Card title="Swing picks (24 jam)" icon="🎯">
              <SwingPicks picks={state.swingPicks} />
            </Card>

            <Card title="Paper trade stats" icon="📊">
              <PaperTradeStatsView data={state.paperStats} />
            </Card>

            <Card title="Open trades" icon="💼">
              <OpenTrades trades={state.openTrades} />
            </Card>

            <Card title="Signals terbaru" icon="🔔">
              <SignalsTable signals={state.signals} closes={state.closes} />
            </Card>
          </>
        )}
      </main>
    </div>
  );
}
