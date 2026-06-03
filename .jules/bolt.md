# Bolt Journal - Critical Learnings

## 2026-02-21 - [Caching local icon resolution]
**Learning:** Resolving local application icons by scanning `/Applications` and checking for existence of paths is a significant disk I/O bottleneck, especially when scrolling through long lists of packages. Using `static let` for a one-time directory listing cache and `NSCache` for resolved paths significantly reduces UI lag.
**Action:** Always prefer caching filesystem metadata and path resolution results when they are used in high-frequency UI paths like list rendering.

## 2024-05-28 - [Optimizing Render Loop Complexity]
**Learning:** In SwiftUI views with large collections, performing `.filter` inside a `ForEach` that iterates over categories creates $O(N \times C)$ complexity. This causes significant frame drops when scrolling or searching through thousands of packages.
**Action:** Pre-calculate a grouped dictionary using `Dictionary(grouping:by:)` before the `body` loop to reduce complexity to $O(N)$ and ensure $O(1)$ lookups during rendering.

## 2026-06-03 - [Centralizing Recommendation Logic]
**Learning:** Moving complex recommendation filtering and matching rules from a SwiftUI view's computed property into an ObservableObject's state-update path removes O(N) overhead from the render loop. Combining rule-based recommendations with a scored candidate list ensures a consistent user experience without frame drops.
**Action:** Always move data-heavy filtering or sorting logic out of SwiftUI views and into a dedicated state manager where results can be cached or computed as needed.
