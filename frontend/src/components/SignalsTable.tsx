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
