//! Security-scoped bookmark management for macOS
//!
//! Persists file access permissions across app restarts for:
//! - External drives (/Volumes/*)
//! - Network shares (SMB, NFS, AFP)
//! - User-selected project directories

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

/// Bookmark data that can be serialized to disk
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookmarkEntry {
    /// Original path that was bookmarked
    pub path: String,
    /// Base64-encoded security-scoped bookmark data (macOS only)
    pub bookmark_data: String,
    /// Whether this is an external/network volume
    pub is_external: bool,
    /// Last access timestamp (unix seconds)
    pub last_accessed: u64,
}

/// Manages security-scoped bookmarks for persistent file access
pub struct BookmarkManager {
    /// Active bookmarks keyed by path
    bookmarks: RwLock<HashMap<String, BookmarkEntry>>,
    /// Paths currently being accessed (started but not stopped)
    #[allow(dead_code)]
    active_access: RwLock<Vec<String>>,
}

impl Default for BookmarkManager {
    fn default() -> Self {
        Self::new()
    }
}

impl BookmarkManager {
    pub fn new() -> Self {
        Self {
            bookmarks: RwLock::new(HashMap::new()),
            active_access: RwLock::new(Vec::new()),
        }
    }

    /// Check if a path is on an external or network volume
    pub fn is_external_or_network(path: &str) -> bool {
        let path = Path::new(path);

        // Check for /Volumes (external drives)
        if path.starts_with("/Volumes") {
            // /Volumes/Macintosh HD is the boot volume, not external
            let components: Vec<_> = path.components().collect();
            if components.len() >= 3 {
                let volume_name = components[2].as_os_str().to_string_lossy();
                // Common boot volume names
                if volume_name == "Macintosh HD"
                    || volume_name == "Macintosh HD - Data"
                    || volume_name == "System"
                {
                    return false;
                }
                return true;
            }
        }

        // Check for network mount points
        if path.starts_with("/net/") || path.starts_with("/Network/") {
            return true;
        }

        // Check for common network path patterns
        let path_str = path.to_string_lossy();
        if path_str.contains("smb://")
            || path_str.contains("nfs://")
            || path_str.contains("afp://")
        {
            return true;
        }

        false
    }

    /// Load bookmarks from persistent storage
    pub fn load_from_store(&self, entries: Vec<BookmarkEntry>) {
        let mut bookmarks = self.bookmarks.write().unwrap();
        for entry in entries {
            log::info!("Loaded bookmark for: {}", entry.path);
            bookmarks.insert(entry.path.clone(), entry);
        }
    }

    /// Get all bookmarks for persistence
    pub fn get_all_bookmarks(&self) -> Vec<BookmarkEntry> {
        self.bookmarks.read().unwrap().values().cloned().collect()
    }

    /// Check if we have a valid bookmark for a path
    pub fn has_bookmark(&self, path: &str) -> bool {
        self.bookmarks.read().unwrap().contains_key(path)
    }

    /// Get bookmark for a path
    pub fn get_bookmark(&self, path: &str) -> Option<BookmarkEntry> {
        self.bookmarks.read().unwrap().get(path).cloned()
    }

    /// Remove a bookmark
    pub fn remove_bookmark(&self, path: &str) -> Option<BookmarkEntry> {
        self.bookmarks.write().unwrap().remove(path)
    }
}

// macOS-specific implementation
#[cfg(target_os = "macos")]
mod macos {
    use super::*;
    use std::ffi::c_void;

    // Core Foundation type aliases
    type CFAllocatorRef = *const c_void;
    type CFURLRef = *const c_void;
    type CFDataRef = *const c_void;
    type CFErrorRef = *mut c_void;
    type CFIndex = isize;
    type CFURLBookmarkCreationOptions = u64;
    type CFURLBookmarkResolutionOptions = u64;
    type Boolean = u8;

    const K_CF_ALLOCATOR_DEFAULT: CFAllocatorRef = std::ptr::null();
    const K_CF_URL_BOOKMARK_CREATION_WITH_SECURITY_SCOPE: CFURLBookmarkCreationOptions = 1 << 11;
    const K_CF_URL_BOOKMARK_RESOLUTION_WITH_SECURITY_SCOPE: CFURLBookmarkResolutionOptions = 1 << 10;

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFURLCreateFromFileSystemRepresentation(
            allocator: CFAllocatorRef,
            buffer: *const u8,
            buf_len: CFIndex,
            is_directory: Boolean,
        ) -> CFURLRef;

        fn CFURLCreateBookmarkData(
            allocator: CFAllocatorRef,
            url: CFURLRef,
            options: CFURLBookmarkCreationOptions,
            resource_properties_to_include: *const c_void,
            relative_to_url: CFURLRef,
            error: *mut CFErrorRef,
        ) -> CFDataRef;

        fn CFURLCreateByResolvingBookmarkData(
            allocator: CFAllocatorRef,
            bookmark: CFDataRef,
            options: CFURLBookmarkResolutionOptions,
            relative_to_url: CFURLRef,
            resource_properties_to_include: *const c_void,
            is_stale: *mut Boolean,
            error: *mut CFErrorRef,
        ) -> CFURLRef;

        fn CFURLStartAccessingSecurityScopedResource(url: CFURLRef) -> Boolean;
        fn CFURLStopAccessingSecurityScopedResource(url: CFURLRef);

        fn CFDataGetLength(data: CFDataRef) -> CFIndex;
        fn CFDataGetBytePtr(data: CFDataRef) -> *const u8;
        fn CFDataCreate(
            allocator: CFAllocatorRef,
            bytes: *const u8,
            length: CFIndex,
        ) -> CFDataRef;

        fn CFURLGetFileSystemRepresentation(
            url: CFURLRef,
            resolve_against_base: Boolean,
            buffer: *mut u8,
            max_buf_len: CFIndex,
        ) -> Boolean;

        fn CFRelease(cf: *const c_void);
    }

    use base64::{engine::general_purpose::STANDARD, Engine};

    impl BookmarkManager {
        /// Create a security-scoped bookmark for a path
        pub fn create_bookmark(&self, path: &str) -> Result<BookmarkEntry, String> {
            let canonical = std::fs::canonicalize(path)
                .map_err(|e| format!("Cannot canonicalize path '{}': {}", path, e))?;

            let path_bytes = canonical.to_string_lossy();
            let path_cstr = path_bytes.as_bytes();
            let is_dir = canonical.is_dir();

            unsafe {
                // Create CFURL from path
                let url = CFURLCreateFromFileSystemRepresentation(
                    K_CF_ALLOCATOR_DEFAULT,
                    path_cstr.as_ptr(),
                    path_cstr.len() as CFIndex,
                    if is_dir { 1 } else { 0 },
                );

                if url.is_null() {
                    return Err("Failed to create CFURL from path".to_string());
                }

                // Create security-scoped bookmark
                let mut error: CFErrorRef = std::ptr::null_mut();
                let bookmark_data = CFURLCreateBookmarkData(
                    K_CF_ALLOCATOR_DEFAULT,
                    url,
                    K_CF_URL_BOOKMARK_CREATION_WITH_SECURITY_SCOPE,
                    std::ptr::null(),
                    std::ptr::null(),
                    &mut error,
                );

                CFRelease(url);

                if bookmark_data.is_null() {
                    return Err("Failed to create security-scoped bookmark".to_string());
                }

                // Get bookmark bytes
                let length = CFDataGetLength(bookmark_data);
                let ptr = CFDataGetBytePtr(bookmark_data);
                let bytes = std::slice::from_raw_parts(ptr, length as usize);

                // Encode as base64
                let encoded = STANDARD.encode(bytes);

                CFRelease(bookmark_data);

                let entry = BookmarkEntry {
                    path: canonical.to_string_lossy().to_string(),
                    bookmark_data: encoded,
                    is_external: Self::is_external_or_network(path),
                    last_accessed: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs(),
                };

                // Store in memory
                self.bookmarks
                    .write()
                    .unwrap()
                    .insert(entry.path.clone(), entry.clone());

                log::info!("Created security-scoped bookmark for: {}", entry.path);

                Ok(entry)
            }
        }

        /// Resolve a bookmark and start accessing the security-scoped resource
        pub fn start_access(&self, entry: &BookmarkEntry) -> Result<PathBuf, String> {
            let bytes = STANDARD
                .decode(&entry.bookmark_data)
                .map_err(|e| format!("Invalid bookmark data: {}", e))?;

            unsafe {
                // Create CFData from bytes
                let cf_data = CFDataCreate(
                    K_CF_ALLOCATOR_DEFAULT,
                    bytes.as_ptr(),
                    bytes.len() as CFIndex,
                );

                if cf_data.is_null() {
                    return Err("Failed to create CFData from bookmark".to_string());
                }

                // Resolve bookmark
                let mut is_stale: Boolean = 0;
                let mut error: CFErrorRef = std::ptr::null_mut();

                let url = CFURLCreateByResolvingBookmarkData(
                    K_CF_ALLOCATOR_DEFAULT,
                    cf_data,
                    K_CF_URL_BOOKMARK_RESOLUTION_WITH_SECURITY_SCOPE,
                    std::ptr::null(),
                    std::ptr::null(),
                    &mut is_stale,
                    &mut error,
                );

                CFRelease(cf_data);

                if url.is_null() {
                    return Err("Failed to resolve security-scoped bookmark".to_string());
                }

                if is_stale != 0 {
                    log::warn!(
                        "Bookmark for '{}' is stale, may need recreation",
                        entry.path
                    );
                }

                // Start accessing the security-scoped resource
                let started = CFURLStartAccessingSecurityScopedResource(url);

                if started == 0 {
                    CFRelease(url);
                    return Err("Failed to start accessing security-scoped resource".to_string());
                }

                // Get path from URL
                let mut buffer = [0u8; 4096];
                let success = CFURLGetFileSystemRepresentation(
                    url,
                    1,
                    buffer.as_mut_ptr(),
                    buffer.len() as CFIndex,
                );

                if success == 0 {
                    CFURLStopAccessingSecurityScopedResource(url);
                    CFRelease(url);
                    return Err("Failed to get path from resolved URL".to_string());
                }

                // Find null terminator
                let len = buffer.iter().position(|&b| b == 0).unwrap_or(buffer.len());
                let path_str = String::from_utf8_lossy(&buffer[..len]).to_string();

                // Track active access
                self.active_access.write().unwrap().push(entry.path.clone());

                // Note: We intentionally don't release the URL here because we need
                // to keep the security-scoped access active. The URL will be released
                // when stop_access is called.

                log::info!("Started security-scoped access for: {}", path_str);

                Ok(PathBuf::from(path_str))
            }
        }

        /// Stop accessing a security-scoped resource
        pub fn stop_access(&self, path: &str) {
            let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| PathBuf::from(path));
            let path_bytes = canonical.to_string_lossy();
            let path_cstr = path_bytes.as_bytes();

            unsafe {
                let url = CFURLCreateFromFileSystemRepresentation(
                    K_CF_ALLOCATOR_DEFAULT,
                    path_cstr.as_ptr(),
                    path_cstr.len() as CFIndex,
                    if canonical.is_dir() { 1 } else { 0 },
                );

                if !url.is_null() {
                    CFURLStopAccessingSecurityScopedResource(url);
                    CFRelease(url);
                    log::info!("Stopped security-scoped access for: {}", path);
                }
            }

            // Remove from active access
            self.active_access.write().unwrap().retain(|p| p != path);
        }

        /// Stop all active access (call on app shutdown)
        pub fn stop_all_access(&self) {
            let paths: Vec<String> = self.active_access.read().unwrap().clone();
            for path in paths {
                self.stop_access(&path);
            }
        }
    }
}

// Non-macOS stub implementations
#[cfg(not(target_os = "macos"))]
impl BookmarkManager {
    /// Create a bookmark (no-op on non-macOS)
    pub fn create_bookmark(&self, path: &str) -> Result<BookmarkEntry, String> {
        let entry = BookmarkEntry {
            path: path.to_string(),
            bookmark_data: String::new(),
            is_external: Self::is_external_or_network(path),
            last_accessed: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        };
        self.bookmarks
            .write()
            .unwrap()
            .insert(entry.path.clone(), entry.clone());
        Ok(entry)
    }

    /// Start access (no-op on non-macOS)
    pub fn start_access(&self, entry: &BookmarkEntry) -> Result<PathBuf, String> {
        Ok(PathBuf::from(&entry.path))
    }

    /// Stop access (no-op on non-macOS)
    pub fn stop_access(&self, _path: &str) {}

    /// Stop all access (no-op on non-macOS)
    pub fn stop_all_access(&self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_external_or_network() {
        // External drives
        assert!(BookmarkManager::is_external_or_network("/Volumes/USB Drive"));
        assert!(BookmarkManager::is_external_or_network(
            "/Volumes/External SSD/project"
        ));

        // Boot volume - not external
        assert!(!BookmarkManager::is_external_or_network("/Volumes/Macintosh HD"));
        assert!(!BookmarkManager::is_external_or_network(
            "/Volumes/Macintosh HD - Data"
        ));

        // Network mounts
        assert!(BookmarkManager::is_external_or_network("/net/server/share"));
        assert!(BookmarkManager::is_external_or_network("/Network/Servers/nas"));

        // Regular paths
        assert!(!BookmarkManager::is_external_or_network("/Users/me/projects"));
        assert!(!BookmarkManager::is_external_or_network("/tmp"));
    }

    #[test]
    fn test_bookmark_manager_basic() {
        let manager = BookmarkManager::new();

        // Initially empty
        assert!(manager.get_all_bookmarks().is_empty());
        assert!(!manager.has_bookmark("/some/path"));

        // Load bookmarks
        let entries = vec![BookmarkEntry {
            path: "/test/path".to_string(),
            bookmark_data: "dGVzdA==".to_string(),
            is_external: false,
            last_accessed: 12345,
        }];

        manager.load_from_store(entries);

        assert!(manager.has_bookmark("/test/path"));
        assert_eq!(manager.get_all_bookmarks().len(), 1);

        // Get bookmark
        let entry = manager.get_bookmark("/test/path").unwrap();
        assert_eq!(entry.path, "/test/path");

        // Remove bookmark
        manager.remove_bookmark("/test/path");
        assert!(!manager.has_bookmark("/test/path"));
    }
}
