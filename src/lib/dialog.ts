import { open } from "@tauri-apps/plugin-dialog";
import { invoke } from "@tauri-apps/api/core";
import { Store } from "@tauri-apps/plugin-store";

const BOOKMARKS_STORE_KEY = "security_bookmarks";
const BOOKMARKS_STORE_FILE = "bookmarks.json";

interface BookmarkEntry {
  path: string;
  bookmark_data: string;
  is_external: boolean;
  last_accessed: number;
}

/**
 * Initialize bookmark system - call on app startup
 */
export async function initBookmarks(): Promise<void> {
  try {
    const store = await Store.load(BOOKMARKS_STORE_FILE);
    const saved = await store.get<BookmarkEntry[]>(BOOKMARKS_STORE_KEY);
    if (saved && saved.length > 0) {
      await invoke("load_bookmarks", { entries: saved });
      console.log(`Loaded ${saved.length} security-scoped bookmarks`);
    }
  } catch (e) {
    console.warn("Failed to load bookmarks:", e);
  }
}

/**
 * Save bookmarks to persistent storage
 */
async function saveBookmarks(): Promise<void> {
  try {
    const bookmarks = await invoke<BookmarkEntry[]>("get_all_bookmarks");
    const store = await Store.load(BOOKMARKS_STORE_FILE);
    await store.set(BOOKMARKS_STORE_KEY, bookmarks);
    await store.save();
  } catch (e) {
    console.warn("Failed to save bookmarks:", e);
  }
}

/**
 * Pick a project folder with automatic bookmark creation for external/network drives
 */
export async function pickProjectFolder(): Promise<string | null> {
  const selected = await open({
    directory: true,
    multiple: false,
    title: "Open Project",
  });

  if (!selected) {
    return null;
  }

  // Check if this path needs a bookmark (external/network drive)
  const needsBookmark = await invoke<boolean>("needs_bookmark", {
    path: selected,
  });

  if (needsBookmark) {
    try {
      // Create security-scoped bookmark
      await invoke("create_bookmark", { path: selected });
      await saveBookmarks();
      console.log(`Created security-scoped bookmark for: ${selected}`);
    } catch (e) {
      console.warn("Failed to create bookmark (access may not persist):", e);
    }
  }

  return selected;
}

/**
 * Start accessing a path - call before file operations on external/network drives
 * Returns the resolved path (may differ from original if bookmark was used)
 */
export async function startPathAccess(path: string): Promise<string> {
  const hasBookmark = await invoke<boolean>("has_bookmark", { path });

  if (hasBookmark) {
    try {
      const resolved = await invoke<string>("start_bookmark_access", { path });
      return resolved;
    } catch (e) {
      console.warn("Bookmark access failed, trying direct access:", e);
    }
  }

  return path;
}

/**
 * Stop accessing a path - call when done with file operations
 */
export async function stopPathAccess(path: string): Promise<void> {
  try {
    await invoke("stop_bookmark_access", { path });
  } catch {
    // Ignore - path may not have been bookmarked
  }
}

/**
 * Wrapper for file operations on potentially bookmarked paths
 */
export async function withPathAccess<T>(
  path: string,
  operation: (resolvedPath: string) => Promise<T>
): Promise<T> {
  const resolvedPath = await startPathAccess(path);
  try {
    return await operation(resolvedPath);
  } finally {
    await stopPathAccess(path);
  }
}
