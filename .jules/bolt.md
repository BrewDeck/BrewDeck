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

## 2026-07-03 - [Optimizing SwiftUI Render Loops via Stored Derived Properties]
**Learning:** Using computed properties that perform string parsing or `UserDefaults` lookups (like `hasUpdate` or `rating`) inside SwiftUI list rows causes significant performance degradation. Converting these to stored properties that are updated only when relevant state changes (e.g., during initialization or version updates) eliminates redundant O(N) overhead during UI render cycles.
**Action:** Prefer stored properties and centralized "derived state update" methods for any metadata used in high-frequency UI paths.
