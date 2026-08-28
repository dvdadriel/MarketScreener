const OPEN_HOUR = 9;
const CLOSE_HOUR = 16;

const WIB_FORMATTER = new Intl.DateTimeFormat("en-US", {
  timeZone: "Asia/Jakarta",
  weekday: "short",
  hour: "numeric",
  hourCycle: "h23",
});

// IDX buka Senin-Jumat 09:00-16:00 WIB. Dihitung di client, tidak perlu
// query DB — lihat DashboardController#index (@idx_open) di Rails lama.
export function isIdxOpenNow(now: Date = new Date()): boolean {
  const parts = WIB_FORMATTER.formatToParts(now);
  const weekday = parts.find((p) => p.type === "weekday")?.value;
  const hour = Number(parts.find((p) => p.type === "hour")?.value);

  if (weekday === "Sun" || weekday === "Sat") return false;
  return hour >= OPEN_HOUR && hour < CLOSE_HOUR;
}
