import { GitFork } from "lucide-react";
import { useCallback, useState } from "react";
import type { GraphNode } from "../../lib/graphLayout";
import { useGitStore } from "../../stores/useGitStore";
import { CommitDetailPanel } from "./CommitDetailPanel";
import { CommitGraph } from "./CommitGraph";

interface GitGraphPanelProps {
  open: boolean;
  onClose: () => void;
  repoPath: string | null;
  currentBranch: string | null;
}

export function GitGraphPanel({
  open,
  onClose: _onClose,
  repoPath,
  currentBranch,
}: GitGraphPanelProps) {
  const [selectedNode, setSelectedNode] = useState<GraphNode | null>(null);

  const { checkoutBranch, createBranch } = useGitStore();

  // Handle commit selection
  const handleSelectCommit = useCallback((node: GraphNode) => {
    setSelectedNode(node);
  }, []);

  // Handle closing detail panel
  const handleCloseDetail = useCallback(() => {
    setSelectedNode(null);
  }, []);

  // Handle create branch at commit
  const handleCreateBranchAtCommit = useCallback(
    async (commitHash: string) => {
      if (!repoPath) return;

      const branchName = window.prompt("Enter new branch name:");
      if (!branchName) return;

      try {
        await createBranch(repoPath, branchName, commitHash);
      } catch (err) {
        console.error("Failed to create branch:", err);
        window.alert(`Failed to create branch: ${err}`);
      }
    },
    [repoPath, createBranch]
  );

  // Handle checkout commit
  const handleCheckoutCommit = useCallback(
    async (commitHash: string) => {
      if (!repoPath) return;

      const confirm = window.confirm(
        "This will checkout a detached HEAD. Continue?"
      );
      if (!confirm) return;

      try {
        await checkoutBranch(repoPath, commitHash);
      } catch (err) {
        console.error("Failed to checkout commit:", err);
        window.alert(`Failed to checkout: ${err}`);
      }
    },
    [repoPath, checkoutBranch]
  );

  const hasRepo = Boolean(repoPath);

  return (
    <aside
      aria-hidden={!open}
      tabIndex={open ? undefined : -1}
      {...(!open ? ({ inert: "" } as { inert: "" }) : {})}
      className={`relative z-30 flex flex-row border-l border-maestro-border bg-maestro-surface transition-all duration-200 overflow-hidden ${
        open ? "w-[560px]" : "w-0 border-l-0"
      }`}
    >
      {/* Main graph panel */}
      <div className="flex min-w-[320px] flex-1 flex-col">
        {/* Content */}
        {!hasRepo ? (
          // Empty state - no repo
          <div className="flex flex-1 items-center justify-center px-4 text-center">
            <div className="flex flex-col items-center gap-3">
              <GitFork
                size={32}
                className="animate-breathe text-maestro-muted/30"
                strokeWidth={1}
              />
              <p className="text-xs text-maestro-muted/60">
                Open a git repository to view commits
              </p>
            </div>
          </div>
        ) : (
          // Commit graph - repoPath is guaranteed to be non-null here since hasRepo is true
          <CommitGraph
            repoPath={repoPath!}
            onSelectCommit={handleSelectCommit}
            selectedCommitHash={selectedNode?.commit.hash ?? null}
            currentBranch={currentBranch}
          />
        )}
      </div>

      {/* Detail panel */}
      {selectedNode && repoPath && (
        <div className="w-60 shrink-0">
          <CommitDetailPanel
            node={selectedNode}
            repoPath={repoPath}
            onClose={handleCloseDetail}
            onCreateBranchAtCommit={handleCreateBranchAtCommit}
            onCheckoutCommit={handleCheckoutCommit}
          />
        </div>
      )}
    </aside>
  );
}
