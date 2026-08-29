// ponytail: kasar tapi cukup — cocok dengan gaya time_ago_in_words Rails
// (tahun/bulan/hari/jam/menit), tidak perlu presisi detik untuk dashboard ini.
export function timeAgo(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diffMs / 60000);
  if (minutes < 1) return "kurang dari semenit";
  if (minutes < 60) return `${minutes} menit`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} jam`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} hari`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months} bulan`;
  return `${Math.floor(months / 12)} tahun`;
}

export function idr(n: number): string {
  return new Intl.NumberFormat("id-ID").format(Math.round(n));
}
