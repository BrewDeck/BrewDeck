# Bolt Journal - Critical Learnings

## 2026-02-21 - [Caching local icon resolution]
**Learning:** Resolving local application icons by scanning `/Applications` and checking for existence of paths is a significant disk I/O bottleneck, especially when scrolling through long lists of packages. Using `static let` for a one-time directory listing cache and `NSCache` for resolved paths significantly reduces UI lag.
**Action:** Always prefer caching filesystem metadata and path resolution results when they are used in high-frequency UI paths like list rendering.

## 2024-05-28 - [Optimizing Render Loop Complexity]
**Learning:** In SwiftUI views with large collections, performing `.filter` inside a `ForEach` that iterates over categories creates $O(N \times C)$ complexity. This causes significant frame drops when scrolling or searching through thousands of packages.
**Action:** Pre-calculate a grouped dictionary using `Dictionary(grouping:by:)` before the `body` loop to reduce complexity to $O(N)$ and ensure $O(1)$ lookups during rendering.

## 2024-05-28 - [Eliminating Redundant String Allocations and Categorization Logic]
**Learning:** Computed properties that perform string lowercasing and multiple substring searches (like `BrewPackage.category`) are a major source of CPU and memory overhead during list rendering and grouping. Converting these to stored properties calculated once via `localizedCaseInsensitiveContains` significantly reduces overhead.
**Action:** Always memoize derived metadata in core models that are used in high-frequency UI paths like list grouping and filtering. Use `localizedCaseInsensitiveContains` to avoid redundant string allocations.

## 2026-02-21 - [Optimizing lookup complexity in large datasets]
**Learning:** Using `Array.contains` inside a `.filter` closure on a large collection (like `self.packages`) leads to $O(N \times M)$ complexity. When the array contains thousands of items, this results in noticeable hangs.
**Action:** Convert the lookup array into a `Set` before filtering to achieve $O(N)$ complexity.

## 2026-02-21 - [Avoiding redundant UserDefaults and parsing in models]
**Learning:** Computed properties that access `UserDefaults` or perform version string parsing (like `BrewPackage.hasUpdate` or `rating`) are expensive when called repeatedly in UI lists.
**Action:** Convert computed properties into stored properties. Use `didSet` observers on the source fields (like `version` and `installedVersion`) and update the stored state in initializers and mutation methods to keep them in sync.
