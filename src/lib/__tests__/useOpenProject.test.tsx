import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";

// Mock modules before imports
const mockOpenProject = vi.fn();
vi.mock("@/stores/useWorkspaceStore", () => ({
  useWorkspaceStore: (selector: (s: { openProject: typeof mockOpenProject }) => unknown) =>
    selector({ openProject: mockOpenProject }),
}));

vi.mock("@/lib/dialog", () => ({
  pickProjectFolder: vi.fn(),
}));

vi.mock("@/lib/permissions", () => ({
  ensurePathAccess: vi.fn(),
  checkFullDiskAccess: vi.fn(),
}));

import { useOpenProject } from "../useOpenProject";
import { pickProjectFolder } from "@/lib/dialog";
import { ensurePathAccess, checkFullDiskAccess } from "@/lib/permissions";

const mockPickProjectFolder = vi.mocked(pickProjectFolder);
const mockEnsurePathAccess = vi.mocked(ensurePathAccess);
const mockCheckFullDiskAccess = vi.mocked(checkFullDiskAccess);

describe("useOpenProject", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it("returns the expected shape", () => {
    const { result } = renderHook(() => useOpenProject());
    expect(result.current).toHaveProperty("openProject");
    expect(result.current).toHaveProperty("showFDADialog");
    expect(result.current).toHaveProperty("fdaPath");
    expect(result.current).toHaveProperty("dismissFDADialog");
    expect(result.current).toHaveProperty("dismissFDADialogPermanently");
    expect(result.current).toHaveProperty("retryAfterFDAGrant");
    expect(typeof result.current.openProject).toBe("function");
    expect(result.current.showFDADialog).toBe(false);
    expect(result.current.fdaPath).toBeNull();
  });

  it("opens project directly for non-FDA paths", async () => {
    mockPickProjectFolder.mockResolvedValue("/Users/john/Projects/repo");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: true, needsFDA: false });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(mockOpenProject).toHaveBeenCalledWith("/Users/john/Projects/repo");
    expect(result.current.showFDADialog).toBe(false);
  });

  it("opens project directly when FDA path has access", async () => {
    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: true, needsFDA: true });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(mockOpenProject).toHaveBeenCalledWith("/Users/john/Desktop/project");
    expect(result.current.showFDADialog).toBe(false);
  });

  it("shows FDA dialog for FDA paths without access", async () => {
    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(mockOpenProject).not.toHaveBeenCalled();
    expect(result.current.showFDADialog).toBe(true);
    expect(result.current.fdaPath).toBe("/Users/john/Desktop/project");
  });

  it("does nothing when user cancels folder picker", async () => {
    mockPickProjectFolder.mockResolvedValue(null);

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(mockOpenProject).not.toHaveBeenCalled();
    expect(result.current.showFDADialog).toBe(false);
  });

  it("dismissFDADialog clears state without opening project", async () => {
    // First trigger the dialog
    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(result.current.showFDADialog).toBe(true);

    act(() => {
      result.current.dismissFDADialog();
    });

    expect(result.current.showFDADialog).toBe(false);
    expect(result.current.fdaPath).toBeNull();
    expect(mockOpenProject).not.toHaveBeenCalled();
  });

  it("dismissFDADialogPermanently sets localStorage flag, clears state, does NOT open project", async () => {
    // First trigger the dialog
    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(result.current.showFDADialog).toBe(true);

    act(() => {
      result.current.dismissFDADialogPermanently();
    });

    expect(result.current.showFDADialog).toBe(false);
    expect(result.current.fdaPath).toBeNull();
    expect(localStorage.getItem("maestro:permissions:fda-dismissed")).toBe("true");
    // Fix 2: should NOT try to open the project
    expect(mockOpenProject).not.toHaveBeenCalled();
  });

  it("retryAfterFDAGrant opens project when access is now granted", async () => {
    // Trigger the dialog
    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    expect(result.current.showFDADialog).toBe(true);

    // Now simulate user granting access
    mockCheckFullDiskAccess.mockResolvedValue(true);

    await act(async () => {
      await result.current.retryAfterFDAGrant();
    });

    expect(mockOpenProject).toHaveBeenCalledWith("/Users/john/Desktop/project");
    expect(result.current.showFDADialog).toBe(false);
    expect(result.current.fdaPath).toBeNull();
  });

  it("retryAfterFDAGrant keeps dialog open when still no access", async () => {
    // Trigger the dialog
    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    // Still no access
    mockCheckFullDiskAccess.mockResolvedValue(false);

    await act(async () => {
      await result.current.retryAfterFDAGrant();
    });

    expect(mockOpenProject).not.toHaveBeenCalled();
    expect(result.current.showFDADialog).toBe(true);
  });

  it("dismissed flag skips dialog on subsequent FDA paths", async () => {
    // Set dismissed flag
    localStorage.setItem("maestro:permissions:fda-dismissed", "true");

    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });
    mockCheckFullDiskAccess.mockResolvedValue(false);

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    // Should skip dialog and try to open directly
    expect(result.current.showFDADialog).toBe(false);
    expect(mockOpenProject).toHaveBeenCalledWith("/Users/john/Desktop/project");
  });

  it("dismissed flag auto-clears when FDA is later granted (Fix 4)", async () => {
    // Set dismissed flag
    localStorage.setItem("maestro:permissions:fda-dismissed", "true");

    mockPickProjectFolder.mockResolvedValue("/Users/john/Desktop/project");
    mockEnsurePathAccess.mockResolvedValue({ hasAccess: false, needsFDA: true });
    // FDA has been granted since dismissal
    mockCheckFullDiskAccess.mockResolvedValue(true);

    const { result } = renderHook(() => useOpenProject());

    await act(async () => {
      await result.current.openProject();
    });

    // Should clear the dismissed flag
    expect(localStorage.getItem("maestro:permissions:fda-dismissed")).toBeNull();
    // And open the project
    expect(mockOpenProject).toHaveBeenCalledWith("/Users/john/Desktop/project");
  });
});
