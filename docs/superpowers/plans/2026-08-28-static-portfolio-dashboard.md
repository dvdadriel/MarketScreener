# Static Portfolio Dashboard (React + Vercel + Supabase) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Materialize the dashboard's read-only data (signals, paper trades, candle closes, momentum forward-tracking, paper-trade stats) into Supabase in a form a static React frontend can query directly, then build and deploy that frontend to Vercel — so the portfolio dashboard is online 24/7 without any Ruby web server.

**Architecture:** GitHub Actions (Ruby, already scheduled) keeps writing to Supabase as today, plus one new step that materializes two path-dependent computations (`MomentumPaperTracker`, `PaperTradeStats`) into two small summary tables. Supabase's auto-generated REST API (PostgREST), locked down with default-deny RLS and narrow anon read policies, serves everything to a static React (Vite) app deployed on Vercel. No custom backend, no Vercel functions.

**Tech Stack:** Ruby on Rails 8 (migrations, model, service, rake task — existing app), Postgres/Supabase (RLS, one view), React 18 + TypeScript + Vite, `@supabase/supabase-js`, Vercel (static hosting).

Reference spec: `docs/superpowers/specs/2026-08-28-static-portfolio-dashboard-design.md`

---

### Task 1: Migration — dashboard summary tables + latest-close view

**Files:**
- Create: `db/migrate/20260828120000_create_dashboard_summary_tables.rb`

- [ ] **Step 1: Write the migration**

```ruby
class CreateDashboardSummaryTables < ActiveRecord::Migration[8.1]
  def up
    create_table :momentum_tracker_summaries do |t|
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    create_table :paper_trade_stats_summaries do |t|
      t.string :asset_type, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :paper_trade_stats_summaries, :asset_type, unique: true

    execute <<~SQL
      CREATE VIEW latest_candle_closes AS
      SELECT DISTINCT ON (symbol, timeframe, asset_type)
        symbol, timeframe, asset_type, close, opened_at
      FROM candles
      ORDER BY symbol, timeframe, asset_type, opened_at DESC;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS latest_candle_closes;"
    drop_table :paper_trade_stats_summaries
    drop_table :momentum_tracker_summaries
  end
end
```

- [ ] **Step 2: Run the migration locally**

Run: `bin/rails db:migrate`
Expected: `== CreateDashboardSummaryTables: migrated` with no errors, and
`db/schema.rb` now lists `momentum_tracker_summaries`, `paper_trade_stats_summaries`.

- [ ] **Step 3: Verify the view manually**

Run: `bin/rails runner 'puts ActiveRecord::Base.connection.execute("SELECT * FROM latest_candle_closes LIMIT 1").to_a'`
Expected: prints `[]` (empty, no candles yet in dev) with no SQL error — confirms the view compiles.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260828120000_create_dashboard_summary_tables.rb db/schema.rb
git commit -m "feat(db): add dashboard summary tables and latest_candle_closes view"
```

---

### Task 2: Models for the summary tables

**Files:**
- Create: `app/models/momentum_tracker_summary.rb`
- Create: `app/models/paper_trade_stats_summary.rb`

- [ ] **Step 1: Write the models**

```ruby
# app/models/momentum_tracker_summary.rb
# Singleton: satu baris, hasil materialize MomentumPaperTracker#call. Dibaca
# langsung oleh dashboard statis (React + Supabase REST) — lihat
# DashboardSummaryMaterializer.
class MomentumTrackerSummary < ApplicationRecord
end
```

```ruby
# app/models/paper_trade_stats_summary.rb
# Satu baris per asset_type ("stock", "crypto"), hasil materialize
# PaperTradeStats.for(asset_type). Dibaca langsung oleh dashboard statis.
class PaperTradeStatsSummary < ApplicationRecord
end
```

- [ ] **Step 2: Sanity-check in console**

Run: `bin/rails runner 'MomentumTrackerSummary.create!(data: { foo: 1 }); puts MomentumTrackerSummary.count; MomentumTrackerSummary.delete_all'`
Expected: prints `1`, no error.

- [ ] **Step 3: Commit**

```bash
git add app/models/momentum_tracker_summary.rb app/models/paper_trade_stats_summary.rb
git commit -m "feat: add MomentumTrackerSummary and PaperTradeStatsSummary models"
```

---

### Task 3: `DashboardSummaryMaterializer` service (TDD)

**Files:**
- Create: `app/services/dashboard_summary_materializer.rb`
- Test: `test/services/dashboard_summary_materializer_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class DashboardSummaryMaterializerTest < ActiveSupport::TestCase
  test "materializes momentum tracker summary" do
    DashboardSummaryMaterializer.new.call

    summary = MomentumTrackerSummary.sole
    assert_equal 0, summary.data["tracked_days"]
    assert_equal 100.0, summary.data["equity"]
  end

  test "materializes paper trade stats summary per asset_type" do
    DashboardSummaryMaterializer.new.call

    summary = PaperTradeStatsSummary.find_by!(asset_type: "stock")
    assert_equal 0, summary.data["total_closed"]
    assert_equal 0, summary.data["open_count"]
  end

  test "re-running upserts instead of duplicating rows" do
    DashboardSummaryMaterializer.new.call
    DashboardSummaryMaterializer.new.call

    assert_equal 1, MomentumTrackerSummary.count
    assert_equal 1, PaperTradeStatsSummary.where(asset_type: "stock").count
  end

  test "serializes best/worst trade as plain hashes, not AR objects" do
    signal = Signal.create!(asset_type: "stock", strategy: "SWING_PICK",
                            symbol: "AAA.JK", fired_at: 2.days.ago)
    PaperTrade.create!(asset_type: "stock", strategy: "SWING_PICK", symbol: "AAA.JK",
                       side: "long", status: "closed", entry_price: 100, entry_at: 2.days.ago,
                       exit_price: 110, exit_at: 1.day.ago, pnl_pct: 10.0,
                       trading_signal_id: signal.id)

    DashboardSummaryMaterializer.new.call

    summary = PaperTradeStatsSummary.find_by!(asset_type: "stock")
    assert_equal "AAA.JK", summary.data["best_trade"]["symbol"]
    assert_equal 10.0, summary.data["best_trade"]["pnl_pct"]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/dashboard_summary_materializer_test.rb`
Expected: FAIL — `NameError: uninitialized constant DashboardSummaryMaterializer`

- [ ] **Step 3: Write the implementation**

```ruby
# app/services/dashboard_summary_materializer.rb
# MomentumPaperTracker dan PaperTradeStats itu perhitungan path-dependent
# (equity curve, rebalancing, drawdown, Sharpe) — bukan agregat SQL biasa.
# Reimplementasi sebagai Postgres view berisiko salah angka, jadi hasil Ruby
# yang sudah teruji ini di-materialize apa adanya ke tabel ringkasan, supaya
# dashboard statis (React + Supabase REST) bisa baca tanpa menjalankan Ruby.
class DashboardSummaryMaterializer
  ASSET_TYPES = %w[stock].freeze

  def call
    materialize_momentum
    ASSET_TYPES.each { |t| materialize_paper_stats(t) }
  end

  private

  def materialize_momentum
    data = MomentumPaperTracker.new.call
    summary = MomentumTrackerSummary.first_or_initialize
    summary.update!(data: data.as_json)
  end

  def materialize_paper_stats(asset_type)
    data = PaperTradeStats.for(asset_type)
    summary = PaperTradeStatsSummary.find_or_initialize_by(asset_type: asset_type)
    summary.update!(data: serialize_stats(data))
  end

  def serialize_stats(data)
    data.merge(
      best_trade: trade_ref(data[:best_trade]),
      worst_trade: trade_ref(data[:worst_trade])
    ).as_json
  end

  def trade_ref(trade)
    return nil unless trade

    trade.as_json(only: %w[symbol strategy pnl_pct exit_at])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/dashboard_summary_materializer_test.rb`
Expected: PASS (4 runs, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/services/dashboard_summary_materializer.rb test/services/dashboard_summary_materializer_test.rb
git commit -m "feat: add DashboardSummaryMaterializer to precompute path-dependent stats"
```

---

### Task 4: Wire the materializer into the daily snapshot task

**Files:**
- Modify: `lib/tasks/idx.rake:14-17`

- [ ] **Step 1: Update the `snapshot` task**

```ruby
  desc "Rekam regime + top-10 momentum harian, forward tracking (17:00 WIB)"
  task snapshot: :environment do
    MomentumSnapshotJob.perform_now
    DashboardSummaryMaterializer.new.call
  end
```

- [ ] **Step 2: Verify the rake task still runs**

Run: `bin/rails runner 'DashboardSummaryMaterializer.new.call; puts "ok"'`
Expected: prints `ok`, no error (this exercises the same code path as `rake idx:snapshot` without needing market data set up).

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/idx.rake
git commit -m "feat: materialize dashboard summaries as part of idx:snapshot"
```

---

### Task 5: Enable RLS default-deny on all public tables

**Files:**
- Create: `db/migrate/20260828120100_enable_rls_default_deny.rb`

- [ ] **Step 1: Write the migration**

```ruby
class EnableRlsDefaultDeny < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      DECLARE r RECORD;
      BEGIN
        FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
        LOOP
          EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', r.tablename);
        END LOOP;
      END $$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Sengaja tidak di-reverse otomatis — mematikan RLS lewat rollback berisiko " \
      "membuka semua tabel produksi ke anon tanpa sadar. Matikan manual per tabel kalau perlu."
  end
end
```

- [ ] **Step 2: Run and verify**

Run: `bin/rails db:migrate`
Expected: migrates cleanly. Then run:
`bin/rails runner 'puts ActiveRecord::Base.connection.execute("SELECT relrowsecurity FROM pg_class WHERE relname = %s" % ActiveRecord::Base.connection.quote("signals")).to_a'`
Expected: `[{"relrowsecurity"=>true}]` — confirms RLS is on. The Rails app itself keeps working (table owner bypasses RLS by default) — run `bin/rails test` to confirm nothing broke.

Run: `bin/rails test`
Expected: full suite still green — RLS being on doesn't affect the app's own DB user.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260828120100_enable_rls_default_deny.rb db/schema.rb
git commit -m "feat(security): enable default-deny RLS on all public tables"
```

---

### Task 6: Anon read-only policies for the dashboard tables

**Files:**
- Create: `db/migrate/20260828120200_add_anon_read_policies_for_dashboard.rb`

- [ ] **Step 1: Write the migration**

```ruby
class AddAnonReadPoliciesForDashboard < ActiveRecord::Migration[8.1]
  TABLES = %w[
    signals
    paper_trades
    candles
    momentum_tracker_summaries
    paper_trade_stats_summaries
  ].freeze

  def up
    TABLES.each do |table|
      # GRANT dulu — RLS policy mengatur baris mana yang boleh dibaca, tapi
      # tanpa GRANT SELECT, role anon tidak boleh menyentuh tabelnya sama
      # sekali. Supabase biasa nge-set default privileges ini otomatis untuk
      # tabel yang dibuat lewat dashboard-nya; karena di sini tabel dibuat
      # lewat migrasi Rails yang connect langsung, GRANT eksplisit lebih aman
      # daripada mengandalkan default privileges yang mungkin belum ke-set.
      execute "GRANT SELECT ON public.#{table} TO anon;"
      execute <<~SQL
        CREATE POLICY anon_read_#{table} ON public.#{table}
          FOR SELECT TO anon USING (true);
      SQL
    end
    execute "GRANT SELECT ON public.latest_candle_closes TO anon;"
  end

  def down
    TABLES.each do |table|
      execute "DROP POLICY IF EXISTS anon_read_#{table} ON public.#{table};"
      execute "REVOKE SELECT ON public.#{table} FROM anon;"
    end
    execute "REVOKE SELECT ON public.latest_candle_closes FROM anon;"
  end
end
```

- [ ] **Step 2: Run and verify**

Run: `bin/rails db:migrate`
Expected: migrates cleanly, no errors (policy names are new, no conflicts).

Run: `bin/rails runner 'puts ActiveRecord::Base.connection.execute("SELECT polname FROM pg_policies WHERE schemaname = %s" % ActiveRecord::Base.connection.quote("public")).to_a'`
Expected: lists the 5 `anon_read_*` policy names.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260828120200_add_anon_read_policies_for_dashboard.rb db/schema.rb
git commit -m "feat(security): allow anon read-only access to dashboard tables"
```

> Note: `candles` is fully open to `anon` (not just via the `latest_candle_closes`
> view) — this is intentional and low-risk: it's public OHLCV market data, not
> user data. Views in Postgres run with the owner's privileges by default, so
> restricting `candles` while leaving the view open wouldn't actually protect
> anything without extra `security_invoker` configuration — simpler and just
> as safe to allow both.

---

### Task 7: Frontend project scaffold

**Files:**
- Create: `frontend/package.json`
- Create: `frontend/vite.config.ts`
- Create: `frontend/tsconfig.json`
- Create: `frontend/index.html`
- Create: `frontend/.env.example`
- Create: `frontend/.gitignore`
- Create: `frontend/src/lib/supabase.ts`
- Create: `frontend/src/lib/idxMarket.ts`
- Create: `frontend/src/types.ts`

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "idx-screener-dashboard",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "typescript": "^5.5.3",
    "vite": "^5.4.0"
  }
}
```

- [ ] **Step 2: Write `vite.config.ts`**

```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
});
```

- [ ] **Step 3: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true
  },
  "include": ["src"]
}
```

- [ ] **Step 4: Write `index.html`**

```html
<!doctype html>
<html lang="id">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>IdxScreener Dashboard</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 5: Write `.env.example` and `.gitignore`**

```
# frontend/.env.example
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

```
# frontend/.gitignore
node_modules
dist
.env
.env.local
```

- [ ] **Step 6: Write `src/lib/supabase.ts`**

```typescript
import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    "VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY belum diset (lihat .env.example)",
  );
}

export const supabase = createClient(url, anonKey);
```

- [ ] **Step 7: Write `src/lib/idxMarket.ts`**

```typescript
const OPEN_HOUR = 9;
const CLOSE_HOUR = 16;

// IDX buka Senin-Jumat 09:00-16:00 WIB. Dihitung di client, tidak perlu
// query DB — lihat DashboardController#index (@idx_open) di Rails lama.
export function isIdxOpenNow(now: Date = new Date()): boolean {
  const wib = new Date(
    now.toLocaleString("en-US", { timeZone: "Asia/Jakarta" }),
  );
  const day = wib.getDay();
  if (day === 0 || day === 6) return false;
  const hour = wib.getHours();
  return hour >= OPEN_HOUR && hour < CLOSE_HOUR;
}
```

- [ ] **Step 8: Write `src/types.ts`**

```typescript
export interface Signal {
  id: number;
  asset_type: string;
  fired_at: string;
  metadata: Record<string, unknown>;
  score: number | null;
  signal_type: string | null;
  strategy: string;
  symbol: string;
}

export interface PaperTrade {
  id: number;
  asset_type: string;
  current_pnl_pct: number | null;
  current_price: number | null;
  entry_at: string;
  entry_price: number;
  exit_at: string | null;
  exit_price: number | null;
  pnl_pct: number | null;
  side: string;
  status: string;
  strategy: string;
  symbol: string;
}

export interface LatestClose {
  symbol: string;
  timeframe: string;
  asset_type: string;
  close: number;
  opened_at: string;
}

export interface MomentumSummaryData {
  inception: string | null;
  as_of: string | null;
  tracked_days: number;
  equity: number;
  total_return: number;
  max_drawdown: number;
  ihsg_return: number | null;
  regime_today: string | null;
  holdings: string[];
  equity_curve: [string, number][];
}

export interface TradeRef {
  symbol: string;
  strategy: string;
  pnl_pct: number;
  exit_at: string;
}

export interface StrategyBreakdown {
  strategy: string;
  total: number;
  wins: number;
  win_rate: number;
  avg_pnl: number;
}

export interface PaperStatsData {
  total_closed: number;
  open_count: number;
  winners: number;
  losers: number;
  win_rate: number;
  avg_pnl: number;
  avg_winner: number;
  avg_loser: number;
  best_trade: TradeRef | null;
  worst_trade: TradeRef | null;
  by_strategy: StrategyBreakdown[];
  expectancy: number;
  profit_factor: number | null;
  max_drawdown: number | null;
  sharpe: number | null;
}
```

- [ ] **Step 9: Install dependencies**

Run: `cd frontend && npm install`
Expected: installs cleanly, creates `node_modules/` and `package-lock.json`.

- [ ] **Step 10: Commit**

```bash
git add frontend/package.json frontend/package-lock.json frontend/vite.config.ts \
  frontend/tsconfig.json frontend/index.html frontend/.env.example frontend/.gitignore \
  frontend/src/lib/supabase.ts frontend/src/lib/idxMarket.ts frontend/src/types.ts
git commit -m "feat(frontend): scaffold Vite + React + TS project with Supabase client"
```

---

### Task 8: Data-fetching components

**Files:**
- Create: `frontend/src/components/SignalsTable.tsx`
- Create: `frontend/src/components/SwingPicks.tsx`
- Create: `frontend/src/components/MomentumSummary.tsx`
- Create: `frontend/src/components/PaperTradeStatsView.tsx`
- Create: `frontend/src/components/OpenTrades.tsx`

- [ ] **Step 1: Write `SignalsTable.tsx`**

```typescript
import type { LatestClose, Signal } from "../types";

interface Props {
  signals: Signal[] | null;
  closes: LatestClose[] | null;
}

export function SignalsTable({ signals, closes }: Props) {
  if (signals === null) return <p>Gagal memuat signals.</p>;
  if (signals.length === 0) return <p>Belum ada signal.</p>;

  const closeBySymbol = new Map((closes ?? []).map((c) => [c.symbol, c.close]));

  return (
    <table>
      <thead>
        <tr>
          <th>Symbol</th>
          <th>Strategy</th>
          <th>Type</th>
          <th>Score</th>
          <th>Last close</th>
          <th>Fired at</th>
        </tr>
      </thead>
      <tbody>
        {signals.map((s) => (
          <tr key={s.id}>
            <td>{s.symbol.replace(".JK", "")}</td>
            <td>{s.strategy}</td>
            <td>{s.signal_type ?? "-"}</td>
            <td>{s.score ?? "-"}</td>
            <td>{closeBySymbol.get(s.symbol) ?? "-"}</td>
            <td>{new Date(s.fired_at).toLocaleString("id-ID")}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

- [ ] **Step 2: Write `SwingPicks.tsx`**

```typescript
import type { Signal } from "../types";

export function SwingPicks({ picks }: { picks: Signal[] | null }) {
  if (picks === null) return <p>Gagal memuat swing picks.</p>;
  if (picks.length === 0) return <p>Tidak ada swing pick baru 24 jam terakhir.</p>;

  return (
    <ul>
      {picks.map((p) => (
        <li key={p.id}>
          {p.symbol.replace(".JK", "")} — rank {String(p.metadata?.rank ?? "-")}
        </li>
      ))}
    </ul>
  );
}
```

- [ ] **Step 3: Write `MomentumSummary.tsx`**

```typescript
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
```

- [ ] **Step 4: Write `PaperTradeStatsView.tsx`**

```typescript
import type { PaperStatsData } from "../types";

export function PaperTradeStatsView({ data }: { data: PaperStatsData | null }) {
  if (data === null) return <p>Gagal memuat paper trade stats.</p>;

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
```

- [ ] **Step 5: Write `OpenTrades.tsx`**

```typescript
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
```

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components
git commit -m "feat(frontend): add dashboard section components"
```

---

### Task 9: Wire up `App.tsx` and `main.tsx`

**Files:**
- Create: `frontend/src/main.tsx`
- Create: `frontend/src/App.tsx`

- [ ] **Step 1: Write `main.tsx`**

```typescript
import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

- [ ] **Step 2: Write `App.tsx`**

```typescript
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
```

- [ ] **Step 3: Run the dev server and check it boots**

Run: `cd frontend && cp .env.example .env.local` (isi dengan URL/anon key Supabase asli), lalu `npm run dev`
Expected: Vite prints a local URL (e.g. `http://localhost:5173`); opening it shows "IdxScreener" and either real data or "Gagal memuat ..." per section (not a blank crash) if Supabase isn't reachable yet.

- [ ] **Step 4: Type-check the build**

Run: `cd frontend && npm run build`
Expected: `tsc -b` and `vite build` both succeed, producing `frontend/dist/`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/main.tsx frontend/src/App.tsx
git commit -m "feat(frontend): wire up dashboard data fetching and layout"
```

---

### Task 10: Vercel deployment config

**Files:**
- Create: `frontend/vercel.json`
- Modify: `docs/idx-screener-deploy-plan.md` (Fase 3 section — add frontend deploy steps)

- [ ] **Step 1: Write `vercel.json`**

```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "framework": "vite"
}
```

- [ ] **Step 2: Append deploy instructions to the plan doc**

Add this subsection right after the existing Fase 3 content in
`docs/idx-screener-deploy-plan.md`:

```markdown
### 3.5 Frontend statis (React) di Vercel

Dashboard read-only sekarang ada di `frontend/` (lihat
docs/superpowers/specs/2026-08-28-static-portfolio-dashboard-design.md).
Deploy terpisah dari Rails:

1. Vercel → New Project → import repo, **Root Directory** = `frontend`
2. Framework preset: Vite (auto-detected dari `vercel.json`)
3. Environment variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
   (anon key publik Supabase — aman diexpose, itu tujuannya, dibatasi RLS)
4. Deploy — Vercel kasih URL `*.vercel.app`, tambahkan custom domain kalau mau
```

- [ ] **Step 3: Commit**

```bash
git add frontend/vercel.json docs/idx-screener-deploy-plan.md
git commit -m "feat(frontend): add Vercel config and deploy instructions"
```

---

### Task 11: Manual verification against the spec

**Files:** none (verification only)

- [ ] **Step 1: Confirm RLS blocks unlisted tables**

From any machine, with the real Supabase anon key:
`curl "https://<project>.supabase.co/rest/v1/solid_queue_jobs?select=*" -H "apikey: $ANON_KEY"`
Expected: `[]` or a permission error — NOT job data (RLS default-deny is working).

- [ ] **Step 2: Confirm the dashboard tables ARE readable**

`curl "https://<project>.supabase.co/rest/v1/signals?select=*&limit=1" -H "apikey: $ANON_KEY"`
Expected: returns a row (or `[]` if no signals yet), not a permission error.

- [ ] **Step 3: Confirm the deployed Vercel site renders real data**

Open the Vercel URL after at least one `rake idx:snapshot` / `rake idx:scanner`
run from GitHub Actions has populated Supabase. Expected: sections show real
numbers, not "Gagal memuat ..." or "Belum ada ...".

- [ ] **Step 4: Confirm a fresh `idx:snapshot` run updates the dashboard**

Trigger `workflow_dispatch` on `.github/workflows/scheduled-jobs.yml` with
`task=snapshot`, wait for it to succeed, then reload the Vercel URL.
Expected: "Forward tracking" section's `as_of` date matches today.
