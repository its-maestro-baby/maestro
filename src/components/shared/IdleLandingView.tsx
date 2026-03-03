import {  Plus } from "lucide-react";
// import ClaudeIcon from "../icons/claude-color.svg";
import claudeColor from "@/components/icons/claude-color.svg";
interface IdleLandingViewProps {
  onAdd: () => void;
}

export function IdleLandingView({ onAdd }: IdleLandingViewProps) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-6">
      <img src={claudeColor} alt="Claude" className="h-14 w-14" />
      {/* Prompt text */}
      <div className="flex flex-col items-center gap-1.5">
        <p className="text-sm text-maestro-muted">Select branch and click Launch</p>
        {/* <p className="text-xs text-maestro-muted/50">Using current branch</p> */}
      </div>

      {/* Centered blue + button */}
      <button
        type="button"
        onClick={onAdd}
        className="flex h-7 w-7 items-center justify-center rounded-full bg-maestro-accent text-white shadow-lg shadow-maestro-accent/25 transition-all duration-200 hover:bg-maestro-accent/90 hover:shadow-maestro-accent/35 hover:scale-105 active:scale-95"
        aria-label="Launch new session"
        title="Launch new session"
      >
        <Plus size={13} strokeWidth={1.5} />
      </button>
    </div>
  );
}
