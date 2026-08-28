import { useEffect, useState } from "react";
import { supabase } from "./lib/supabase";
import { isIdxOpenNow } from "./lib/idxMarket";
import { SignalsTable } from "./components/SignalsTable";
import { SwingPicks } from "./components/SwingPicks";
import { MomentumSummary } from "./components/MomentumSummary";
import { PaperTradeStatsView } from "./components/PaperTradeStatsView";
import { OpenTrades } from "./components/OpenTrades";
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
      setLoading(false);
    }

    load();
  }, []);

  return (
    <main>
      <h1>IdxScreener</h1>
      <p>Market: {isIdxOpenNow() ? "BUKA" : "TUTUP"}</p>

      {loading ? (
        <p>Memuat...</p>
      ) : (
        <>
          <section>
            <h2>Forward tracking (momentum)</h2>
            <MomentumSummary data={state.momentum} />
          </section>

          <section>
            <h2>Swing picks (24 jam)</h2>
            <SwingPicks picks={state.swingPicks} />
          </section>

          <section>
            <h2>Paper trade stats</h2>
            <PaperTradeStatsView data={state.paperStats} />
          </section>

          <section>
            <h2>Open trades</h2>
            <OpenTrades trades={state.openTrades} />
          </section>

          <section>
            <h2>Signals terbaru</h2>
            <SignalsTable signals={state.signals} closes={state.closes} />
          </section>
        </>
      )}
    </main>
  );
}
