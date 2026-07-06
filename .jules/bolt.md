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

## 2026-02-21 - [Eliminating Synchronous Disk I/O and Complex Parsing in UI Paths]
**Learning:** Synchronous `UserDefaults` reads and complex parsing (like version comparison) inside SwiftUI computed properties or list items create cumulative blocking on the main thread during scrolling. Refactoring these to stored properties that are updated only when the source data changes (e.g., via a centralized `updatePackageRating` method) removes these bottlenecks.
**Action:** Use stored properties for any derived state that involves I/O or non-trivial calculation. Manage updates centrally in the data coordinator (Manager) to maintain consistency and UI performance.
