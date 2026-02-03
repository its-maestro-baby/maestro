import { useEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, RefreshCw } from "lucide-react";
import { useUsageStore } from "@/stores/useUsageStore";
import { getMoodDescription, formatResetTime } from "@/lib/usageParser";
import { TamagotchiCharacter } from "./TamagotchiCharacter";

/**
 * Tamagotchi widget that displays Claude Code rate limit usage.
 * Lives in the sidebar footer with usage bar overlaid on the character.
 */
export function Tamagotchi() {
  const { usage, mood, isLoading, error, needsAuth, fetchUsage, startPolling } =
    useUsageStore();
  const containerRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState(120);
  const [showWeekly, setShowWeekly] = useState(false);
  const [testMoodIndex, setTestMoodIndex] = useState<number | null>(null);
  const moods = ["sleeping", "hungry", "bored", "content", "happy"] as const;
  // Mock percentages for each test state
  const mockPercents = [0, 20, 40, 60, 85];

  // Start polling on mount
  useEffect(() => {
    const cleanup = startPolling();
    return cleanup;
  }, [startPolling]);

  // Resize observer to scale with sidebar width
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const width = entry.contentRect.width;
        // Scale size to fill container width
        setSize(Math.max(100, Math.min(width - 16, 220)));
      }
    });

    observer.observe(container);
    return () => observer.disconnect();
  }, []);

  const sessionPercent = usage?.sessionPercent ?? 0;
  const weeklyPercent = usage?.weeklyPercent ?? 0;
  const sessionResetTime = formatResetTime(usage?.sessionResetsAt ?? null);
  const weeklyResetTime = formatResetTime(usage?.weeklyResetsAt ?? null);

  const currentPercent = showWeekly ? weeklyPercent : sessionPercent;
  const currentResetTime = showWeekly ? weeklyResetTime : sessionResetTime;
  const currentLabel = showWeekly ? "Weekly" : "Daily";
  const currentColor = showWeekly ? "bg-maestro-green" : "bg-maestro-accent";

  return (
    <div
      ref={containerRef}
      className="shrink-0 border-t border-maestro-border/60 bg-maestro-surface px-2 py-2"
    >
      {/* Character container with overlaid bar */}
      <div className="relative flex justify-center items-center">
        <button
          type="button"
          onClick={() => setTestMoodIndex(i => i === null ? moods.length - 1 : i === 0 ? null : i - 1)}
          className="absolute left-0 p-1 rounded hover:bg-maestro-border/40 text-maestro-muted hover:text-maestro-text z-10"
          title="Previous state"
        >
          <ChevronLeft size={16} />
        </button>

        <TamagotchiCharacter mood={testMoodIndex !== null ? moods[testMoodIndex] : mood} size={size} />

        {/* Overlaid usage bar - positioned at bottom of character */}
        {!needsAuth && (
          <div
            className="absolute left-0 right-0 px-2"
            style={{ bottom: size * 0.08 }}
          >
            <div className="h-2.5 overflow-hidden rounded-full bg-maestro-border/60">
              <div
                className={`h-full rounded-full ${currentColor} transition-all duration-500`}
                style={{ width: `${Math.min(100, testMoodIndex !== null ? mockPercents[testMoodIndex] : currentPercent)}%` }}
              />
            </div>
          </div>
        )}

        <button
          type="button"
          onClick={() => setTestMoodIndex(i => i === null ? 0 : i === moods.length - 1 ? null : i + 1)}
          className="absolute right-0 p-1 rounded hover:bg-maestro-border/40 text-maestro-muted hover:text-maestro-text z-10"
          title="Next state"
        >
          <ChevronRight size={16} />
        </button>
      </div>

      {/* Test mode indicator */}
      {testMoodIndex !== null && (
        <div className="text-center text-[9px] text-maestro-muted mt-1">
          Testing: {moods[testMoodIndex]} (state {testMoodIndex}, {mockPercents[testMoodIndex]}%)
        </div>
      )}

      {/* Stats row */}
      <div className="flex items-center justify-between mt-2">
        <div className="flex-1 min-w-0">
          {needsAuth ? (
            <div className="text-[10px] text-maestro-muted">
              Run <code className="rounded bg-maestro-border/50 px-1 py-0.5 font-mono">claude</code> to wake
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setShowWeekly(!showWeekly)}
              className="flex items-center gap-1.5 text-[10px] text-maestro-muted hover:text-maestro-text transition-colors"
              title={currentResetTime ? `Resets ${currentResetTime}. Click to toggle.` : "Click to toggle daily/weekly"}
            >
              <span className={`inline-block w-2 h-2 rounded-full ${currentColor}`} />
              <span>{currentLabel}: {Math.round(currentPercent)}%</span>
            </button>
          )}
        </div>
        <button
          type="button"
          onClick={fetchUsage}
          disabled={isLoading}
          className="rounded p-0.5 hover:bg-maestro-border/40 shrink-0"
          title="Refresh usage"
        >
          <RefreshCw
            size={12}
            className={`text-maestro-muted ${isLoading ? "animate-spin" : ""}`}
          />
        </button>
      </div>

      {error && (
        <div className="mt-1 truncate text-[9px] text-maestro-red text-center">{error}</div>
      )}
    </div>
  );
}
