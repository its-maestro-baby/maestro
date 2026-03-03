import { useEffect, useRef } from "react";
import { AlertTriangle } from "lucide-react";
import { useCloseConfirmStore } from "@/stores/useCloseConfirmStore";

export function CloseConfirmDialog() {
  const request = useCloseConfirmStore((s) => s.request);
  const skipConfirm = useCloseConfirmStore((s) => s.skipConfirm);
  const accept = useCloseConfirmStore((s) => s.accept);
  const cancel = useCloseConfirmStore((s) => s.cancel);
  const setSkipConfirm = useCloseConfirmStore((s) => s.setSkipConfirm);
  const dialogRef = useRef<HTMLDivElement>(null);

  // Close on Escape
  useEffect(() => {
    if (!request) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") cancel();
    };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [request, cancel]);

  // Close on backdrop click
  useEffect(() => {
    if (!request) return;
    const handleClick = (e: MouseEvent) => {
      if (dialogRef.current && !dialogRef.current.contains(e.target as Node)) {
        cancel();
      }
    };
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [request, cancel]);

  if (!request) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm">
      <div
        ref={dialogRef}
        className="w-[340px] rounded-xl border border-maestro-border bg-maestro-surface p-5 shadow-2xl"
      >
        {/* Icon + Title */}
        <div className="mb-3 flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-maestro-orange/10">
            <AlertTriangle size={20} className="text-maestro-orange" />
          </div>
          <h3 className="text-sm font-semibold text-maestro-text">{request.title}</h3>
        </div>

        {/* Message */}
        <p className="mb-4 text-xs leading-relaxed text-maestro-muted">{request.message}</p>

        {/* Don't ask again */}
        <label className="mb-4 flex cursor-pointer items-center gap-2 text-xs text-maestro-muted">
          <input
            type="checkbox"
            checked={skipConfirm}
            onChange={(e) => setSkipConfirm(e.target.checked)}
            className="h-3.5 w-3.5 rounded border-maestro-border accent-maestro-accent"
          />
          Don't ask again
        </label>

        {/* Buttons */}
        <div className="flex flex-col gap-2">
          <button
            type="button"
            onClick={accept}
            className="w-full rounded-lg bg-maestro-red/90 px-4 py-2 text-xs font-medium text-white transition-colors hover:bg-maestro-red"
          >
            {request.confirmLabel ?? "Yes, close"}
          </button>
          <button
            type="button"
            onClick={cancel}
            className="w-full rounded-lg bg-maestro-card px-4 py-2 text-xs font-medium text-maestro-text transition-colors hover:bg-maestro-border/60"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
}
