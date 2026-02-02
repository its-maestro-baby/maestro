pub mod error;
pub mod ops;
pub mod runner;

pub use error::GitError;
pub use ops::{BranchInfo, CommitInfo, FileChange, FileChangeStatus, GitUserConfig, RemoteInfo, WorktreeInfo};
pub use runner::Git;
