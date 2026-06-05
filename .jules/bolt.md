# Bolt Journal - Critical Learnings

## 2026-02-21 - [Caching local icon resolution]
**Learning:** Resolving local application icons by scanning `/Applications` and checking for existence of paths is a significant disk I/O bottleneck, especially when scrolling through long lists of packages. Using `static let` for a one-time directory listing cache and `NSCache` for resolved paths significantly reduces UI lag.
**Action:** Always prefer caching filesystem metadata and path resolution results when they are used in high-frequency UI paths like list rendering.

## 2024-05-28 - [Optimizing Render Loop Complexity]
**Learning:** In SwiftUI views with large collections, performing `.filter` inside a `ForEach` that iterates over categories creates $O(N \times C)$ complexity. This causes significant frame drops when scrolling or searching through thousands of packages.
**Action:** Pre-calculate a grouped dictionary using `Dictionary(grouping:by:)` before the `body` loop to reduce complexity to $O(N)$ and ensure $O(1)$ lookups during rendering.

## 2024-05-29 - [Stored vs Computed Properties for Data Categorization]
**Learning:** Using a computed property with multiple `lowercased().contains()` calls for data categorization (like `AppCategory`) causes significant overhead in high-frequency paths (like list filtering and grouping).
**Action:** Convert categorization logic into a stored property calculated once at initialization. Use `localizedCaseInsensitiveContains()` instead of manual `lowercased().contains()` to avoid redundant string allocations and improve performance.
