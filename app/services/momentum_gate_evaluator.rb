# Verdict otomatis kriteria promosi momentum (plan H6, kontrak §1.3 di
# guideline/improvement_plan.md). Kriteria ditulis SEBELUM melihat hasil supaya
# keputusan promosi tak digeser mengikuti angka yang keluar (no goalpost moving).
#
# Kriteria (SEMUA harus terpenuhi):
#   1. duration  — ≥ WEEKS_REQUIRED minggu forward tracking
#   2. alpha     — alpha kumulatif vs IHSG > 0
#   3. drawdown  — maxDD paper ≤ MAX_DD_CEILING
#   4. regime    — tak ada pelanggaran regime (hari risk-off tak boleh punya pick)
class MomentumGateEvaluator
  WEEKS_REQUIRED = 8
  # "≤ 1,5× drawdown backtest window terburuk" — backtest EXTENDED-filtered terburuk
  # ≈9,1% (guideline/docs/2026-07-15-momentum-strategy-report.md §3b) × 1,5 ≈ 14%.
  MAX_DD_CEILING = 14.0

  Verdict = Struct.new(
    :weeks_tracked, :weeks_required, :alpha_cumulative, :max_drawdown,
    :max_dd_ceiling, :regime_consistent, :criteria, :evaluated, :promote,
    keyword_init: true
  )

  def call
    r     = MomentumPaperTracker.new.call
    weeks = r[:inception] ? ((r[:as_of] - r[:inception]).to_i / 7.0).floor : 0
    alpha = r[:ihsg_return] ? (r[:total_return] - r[:ihsg_return]).round(2) : nil
    consistent = regime_consistent?

    criteria = {
      duration: weeks >= WEEKS_REQUIRED,
      alpha:    !alpha.nil? && alpha > 0,
      drawdown: r[:max_drawdown] <= MAX_DD_CEILING,
      regime:   consistent
    }

    Verdict.new(
      weeks_tracked: weeks, weeks_required: WEEKS_REQUIRED, alpha_cumulative: alpha,
      max_drawdown: r[:max_drawdown], max_dd_ceiling: MAX_DD_CEILING,
      regime_consistent: consistent, criteria: criteria,
      evaluated: criteria[:duration],              # kriteria lain baru bermakna setelah durasi cukup
      promote: criteria.values.all?              # :duration ikut di dalamnya
    )
  end

  private

  # Cek data TERSIMPAN (bukan re-derive) — hari risk_off tak boleh punya pick.
  # Given cara MomentumSnapshotJob menulis, ini selalu true; kegagalan = bug/data
  # rusak, bukan sinyal strategi salah. Diverifikasi tetap, bukan diasumsikan.
  def regime_consistent?
    !MomentumSnapshot.where(regime: "risk_off").where.not(symbol: nil).exists?
  end
end
