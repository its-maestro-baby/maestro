import { type BackendSessionStatus, useSessionStore } from "@/stores/useSessionStore";

const STATUS_DEFS: {
  key: BackendSessionStatus;
  label: string;
  colorClass: string;
}[] = [
  { key: "Starting", label: "Starting...", colorClass: "bg-orange-400" },
  { key: "Idle", label: "Idle", colorClass: "bg-maestro-muted" },
  { key: "Working", label: "Working", colorClass: "bg-maestro-accent" },
  { key: "NeedsInput", label: "Needs Input", colorClass: "bg-yellow-300" },
  { key: "Done", label: "Done", colorClass: "bg-maestro-green" },
  { key: "Error", label: "Error", colorClass: "bg-red-400" },
];

export function StatusLegend() {
  const sessions = useSessionStore((s) => s.sessions);
  const counts = sessions.reduce<Record<BackendSessionStatus, number>>(
    (acc, session) => {
      acc[session.status] = (acc[session.status] ?? 0) + 1;
      return acc;
    },
    {
      Starting: 0,
      Idle: 0,
      Working: 0,
      NeedsInput: 0,
      Done: 0,
      Error: 0,
    },
  );

  return (
    <div className="flex items-center gap-3">
      {STATUS_DEFS.map((s) => {
        const count = counts[s.key] ?? 0;
        return (
          <div key={s.key} className="flex items-center gap-1.5">
            <span className={`h-2.5 w-2.5 rounded-full ${s.colorClass}`} />
            <span className="text-[11px] text-maestro-text/70">
              {s.label}
              {count > 0 && <span className="ml-0.5 text-maestro-text/50">({count})</span>}
            </span>
          </div>
        );
      })}
    </div>
  );
}
