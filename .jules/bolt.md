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

## 2024-06-26 - [Optimizing Derived State in Models]
**Learning:** Performing expensive operations like Homebrew version parsing, string formatting, and UserDefaults lookups in computed properties (like `BrewPackage.hasUpdate` and `rating`) causes massive UI stuttering during list scrolling as these are re-evaluated multiple times per frame.
**Action:** Convert these computed properties to stored properties. Update them once during initialization and via `didSet` observers on the source properties (`version`, `installedVersion`). Centralize updates (like ratings) in the manager to ensure consistency.

## 2024-06-26 - [Set-based filtering for recommendation lookups]
**Learning:** Using `Array.contains` inside a filter on a large collection (O(N*M)) creates a measurable bottleneck during recommendation refreshes.
**Action:** Always convert lookup arrays to `Set` before filtering to achieve O(N+M) performance.
