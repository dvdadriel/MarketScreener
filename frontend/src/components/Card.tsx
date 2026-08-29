import type { ReactNode } from "react";

interface Props {
  title: string;
  icon: string;
  children: ReactNode;
}

export function Card({ title, icon, children }: Props) {
  return (
    <section className="rounded-2xl border border-zinc-800 bg-gradient-to-br from-zinc-900 to-zinc-950 p-5">
      <h2 className="mb-4 flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-zinc-400">
        <span className="text-base">{icon}</span>
        {title}
      </h2>
      {children}
    </section>
  );
}
