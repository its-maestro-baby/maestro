use std::collections::HashSet;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::git::{Git, GitError, WorktreeInfo};

fn worktree_base_dir() -> PathBuf {
    directories::ProjectDirs::from("com", "maestro", "maestro")
        .map(|p| p.data_dir().to_path_buf())
        .unwrap_or_else(|| {
            dirs_fallback()
        })
        .join("worktrees")
}

/// Fallback if ProjectDirs fails (e.g., no HOME set).
/// This GUI app assumes a user session on a desktop environment where HOME is set.
/// Panicking here is intentional to fail fast in headless/container/systemd scenarios.
fn dirs_fallback() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .map(|p| p.join(".local").join("share").join("maestro"))
        .expect("HOME environment variable must be set for worktree management")
}

/// Produces a 16-hex-char SHA-256 digest of the canonicalized repo path.
/// Falls back to the raw path if canonicalization fails (e.g., path does not exist yet).
async fn repo_hash(repo_path: &Path) -> String {
    let canonical = tokio::fs::canonicalize(repo_path)
        .await
        .unwrap_or_else(|_| repo_path.to_path_buf());
    let digest = Sha256::digest(canonical.to_string_lossy().as_bytes());
    format!("{:x}", digest)[..16].to_string()
}

/// Replaces filesystem-unsafe characters in branch names with hyphens.
/// Covers `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, and `|`.
/// Also handles `.` and `..` as special cases returning `unnamed-branch`.
fn sanitize_branch(branch: &str) -> String {
    if branch.is_empty() || branch == "." || branch == ".." {
        return "unnamed-branch".to_string();
    }

    let sanitized: String = branch
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '-',
            _ => c,
        })
        .collect();

    sanitized
}

/// Manages Maestro-owned git worktrees under a deterministic, repo-specific
/// directory inside XDG data dirs.
///
/// Worktree paths are derived from a SHA-256 hash of the canonical repo path
/// (truncated to 16 hex chars) so that different repos never collide, and a
/// sanitized branch name so each branch gets its own subdirectory.
pub struct WorktreeManager;

impl Default for WorktreeManager {
    fn default() -> Self {
        Self::new()
    }
}

impl WorktreeManager {
    /// Creates a new stateless manager. All path computation is pure and
    /// deterministic from the repo path and branch name.
    pub fn new() -> Self {
        Self
    }

    /// Compute the worktree path for a given repo + branch
    async fn worktree_path(&self, repo_path: &Path, branch: &str) -> PathBuf {
        let hash = repo_hash(repo_path).await;
        let sanitized = sanitize_branch(branch);
        worktree_base_dir().join(hash).join(sanitized)
    }

    /// Creates a worktree for the given branch, returning its path on disk.
    ///
    /// Checks that the branch is not already checked out in another worktree
    /// before creating (returns `BranchAlreadyCheckedOut` if so). Parent
    /// directories are created automatically. The worktree checks out the
    /// existing branch -- no new branch is created.
    pub async fn create(
        &self,
        branch: &str,
        repo_path: &Path,
    ) -> Result<PathBuf, GitError> {
        let git = Git::new(repo_path);

        // Check if branch is already checked out in another worktree
        let existing = git.worktree_list().await?;
        for wt in &existing {
            if let Some(ref wt_branch) = wt.branch {
                if wt_branch == branch {
                    return Err(GitError::BranchAlreadyCheckedOut {
                        branch: branch.to_string(),
                        path: wt.path.clone(),
                    });
                }
            }
        }

        let wt_path = self.worktree_path(repo_path, branch).await;

        // Create parent directories
        if let Some(parent) = wt_path.parent() {
            tokio::fs::create_dir_all(parent).await.map_err(|e| GitError::SpawnError {
                source: e,
                command: format!("create_dir_all {:?}", parent),
            })?;
        }

        git.worktree_add(&wt_path, None, Some(branch)).await?;

        Ok(wt_path)
    }

    /// Force-removes a worktree and prunes its git ref, then attempts to
    /// clean up the empty parent directory (silently ignored if non-empty).
    pub async fn remove(&self, repo_path: &Path, wt_path: &Path) -> Result<(), GitError> {
        let git = Git::new(repo_path);
        git.worktree_remove(wt_path, true).await?;
        git.worktree_prune().await?;

        // Clean up empty parent directories
        if let Some(parent) = wt_path.parent() {
            let _ = tokio::fs::remove_dir(parent).await; // only succeeds if empty
        }

        Ok(())
    }

    /// Lists only worktrees that live under Maestro's managed base directory,
    /// filtering out the main worktree and any manually created worktrees.
    pub async fn list_managed(&self, repo_path: &Path) -> Result<Vec<WorktreeInfo>, GitError> {
        let git = Git::new(repo_path);
        let all = git.worktree_list().await?;

        let base = worktree_base_dir();

        Ok(all
            .into_iter()
            .filter(|wt| Path::new(&wt.path).starts_with(&base))
            .collect())
    }

    /// Prunes stale git worktree refs and removes orphaned directories.
    ///
    /// First runs `git worktree prune`, then scans the managed directory for
    /// subdirectories that are no longer in git's worktree list. Orphaned
    /// directories are deleted with `remove_dir_all`. No-ops gracefully if
    /// the managed directory does not exist yet.
    pub async fn prune(&self, repo_path: &Path) -> Result<(), GitError> {
        let git = Git::new(repo_path);
        git.worktree_prune().await?;

        // Scan managed directory for orphans not in git worktree list
        let hash = repo_hash(repo_path).await;
        let managed_dir = worktree_base_dir().join(&hash);

        let managed_exists = tokio::fs::try_exists(&managed_dir)
            .await
            .map_err(|e| GitError::SpawnError {
                source: e,
                command: format!("try_exists {:?}", managed_dir),
            })?;
        if !managed_exists {
            return Ok(());
        }

        let active_raw: Vec<String> = git
            .worktree_list()
            .await?
            .iter()
            .map(|wt| wt.path.clone())
            .collect();

        // Canonicalize active paths for reliable comparison; fall back to raw path
        let mut active: HashSet<String> = HashSet::with_capacity(active_raw.len());
        for raw in &active_raw {
            let p = Path::new(raw);
            let canonical = tokio::fs::canonicalize(p).await.unwrap_or_else(|_| p.to_path_buf());
            active.insert(canonical.to_string_lossy().to_string());
        }

        if let Ok(mut entries) = tokio::fs::read_dir(&managed_dir).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                let path = entry.path();
                let canonical_entry = tokio::fs::canonicalize(&path)
                    .await
                    .unwrap_or_else(|_| path.clone());
                let entry_key = canonical_entry.to_string_lossy().to_string();
                let is_dir = tokio::fs::metadata(&path)
                    .await
                    .map(|m| m.is_dir())
                    .unwrap_or(false);
                if !active.contains(&entry_key) && is_dir {
                    log::info!("Removing orphaned worktree dir: {}", path.display());
                    let _ = tokio::fs::remove_dir_all(&path).await;
                }
            }
        }

        Ok(())
    }
}
