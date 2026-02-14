/**
 * Binary split tree for iTerm2-style terminal pane layouts.
 *
 * The tree is immutable — every mutation returns a new tree.
 * Leaf nodes map to session slots; split nodes define how two
 * children are arranged (horizontal = stacked, vertical = side-by-side).
 */

export type SplitDirection = "horizontal" | "vertical";

export interface LeafNode {
  type: "leaf";
  id: string;
  slotId: string;
}

export interface SplitNode {
  type: "split";
  id: string;
  direction: SplitDirection;
  children: [TreeNode, TreeNode];
  /** First child's share of the available space (0.0–1.0). */
  ratio: number;
}

export type TreeNode = LeafNode | SplitNode;

let _nextId = 0;
function uid(): string {
  return `node-${Date.now()}-${++_nextId}`;
}

/** Create a new leaf node for the given slot. */
export function createLeaf(slotId: string): LeafNode {
  return { type: "leaf", id: uid(), slotId };
}

/**
 * Split an existing leaf into a SplitNode containing the original leaf
 * and a new leaf for `newSlotId`.
 *
 * Returns the original tree unchanged if `targetSlotId` is not found.
 */
export function splitLeaf(
  tree: TreeNode,
  targetSlotId: string,
  newSlotId: string,
  direction: SplitDirection,
): TreeNode {
  if (tree.type === "leaf") {
    if (tree.slotId === targetSlotId) {
      return {
        type: "split",
        id: uid(),
        direction,
        children: [tree, createLeaf(newSlotId)],
        ratio: 0.5,
      };
    }
    return tree;
  }

  // Recurse into split children
  const [left, right] = tree.children;
  const newLeft = splitLeaf(left, targetSlotId, newSlotId, direction);
  const newRight = splitLeaf(right, targetSlotId, newSlotId, direction);

  if (newLeft === left && newRight === right) return tree; // no change
  return { ...tree, children: [newLeft, newRight] };
}

/**
 * Remove a leaf from the tree.
 *
 * When a leaf is removed, its sibling is promoted to replace the parent
 * SplitNode. Returns `null` if the root itself is the removed leaf.
 */
export function removeLeaf(tree: TreeNode, slotId: string): TreeNode | null {
  if (tree.type === "leaf") {
    return tree.slotId === slotId ? null : tree;
  }

  const [left, right] = tree.children;

  // Check if either direct child is the target leaf
  if (left.type === "leaf" && left.slotId === slotId) return right;
  if (right.type === "leaf" && right.slotId === slotId) return left;

  // Recurse
  const newLeft = removeLeaf(left, slotId);
  const newRight = removeLeaf(right, slotId);

  // If a subtree collapsed, promote the surviving node
  if (newLeft === null) return newRight;
  if (newRight === null) return newLeft;

  if (newLeft === left && newRight === right) return tree; // no change
  return { ...tree, children: [newLeft, newRight] };
}

/** Update the ratio for a specific split node. */
export function updateRatio(tree: TreeNode, nodeId: string, ratio: number): TreeNode {
  if (tree.type === "leaf") return tree;

  if (tree.id === nodeId) {
    return { ...tree, ratio };
  }

  const [left, right] = tree.children;
  const newLeft = updateRatio(left, nodeId, ratio);
  const newRight = updateRatio(right, nodeId, ratio);

  if (newLeft === left && newRight === right) return tree;
  return { ...tree, children: [newLeft, newRight] };
}

/**
 * Collect all slot IDs in depth-first order (left-to-right, top-to-bottom).
 * This defines the Cmd+1-9 ordering.
 */
export function collectSlotIds(tree: TreeNode): string[] {
  if (tree.type === "leaf") return [tree.slotId];
  const [left, right] = tree.children;
  return [...collectSlotIds(left), ...collectSlotIds(right)];
}

/**
 * Find the sibling slot ID of a given slot in the tree.
 * Returns null if the slot is the root or not found.
 */
export function findSiblingSlotId(tree: TreeNode, slotId: string): string | null {
  if (tree.type === "leaf") return null;

  const [left, right] = tree.children;

  // Check if the target is a direct child
  if (left.type === "leaf" && left.slotId === slotId) {
    // Return first leaf of sibling subtree
    const ids = collectSlotIds(right);
    return ids[0] ?? null;
  }
  if (right.type === "leaf" && right.slotId === slotId) {
    const ids = collectSlotIds(left);
    return ids[0] ?? null;
  }

  // Recurse
  return findSiblingSlotId(left, slotId) ?? findSiblingSlotId(right, slotId);
}
