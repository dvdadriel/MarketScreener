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
