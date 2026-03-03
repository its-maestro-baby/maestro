import {
  Activity,
  FileText,
  GitBranch,
  History,
  Package,
  Server,
  Settings,
  Zap,
} from "lucide-react";

interface CollapsedRailProps {
  onExpand: () => void;
}

const railItems = [
  { icon: GitBranch, label: "Git", color: "text-maestro-green" },
  { icon: FileText, label: "Context", color: "text-maestro-muted" },
  { icon: Package, label: "Plugins", color: "text-maestro-muted" },
  { icon: Server, label: "MCP", color: "text-maestro-muted" },
  { icon: Zap, label: "Quick Actions", color: "text-maestro-muted" },
  { icon: Activity, label: "Processes", color: "text-maestro-muted" },
  { icon: History, label: "Claude Data", color: "text-maestro-muted" },
  { icon: Settings, label: "Appearance", color: "text-maestro-muted" },
];

export function CollapsedRail({ onExpand }: CollapsedRailProps) {
  return (
    <div className="flex flex-col items-center gap-1 py-3 animate-sidebar-fade-in">
      {railItems.map(({ icon: Icon, label, color }) => (
        <button
          key={label}
          type="button"
          title={label}
          onClick={onExpand}
          className="flex h-8 w-8 items-center justify-center rounded-md text-maestro-muted transition-colors hover:bg-maestro-card hover:text-maestro-text"
        >
          <Icon size={16} className={color} />
        </button>
      ))}
    </div>
  );
}
