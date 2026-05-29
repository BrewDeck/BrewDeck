# Bolt Journal - Critical Learnings

## 2026-02-21 - [Caching local icon resolution]
**Learning:** Resolving local application icons by scanning `/Applications` and checking for existence of paths is a significant disk I/O bottleneck, especially when scrolling through long lists of packages. Using `static let` for a one-time directory listing cache and `NSCache` for resolved paths significantly reduces UI lag.
**Action:** Always prefer caching filesystem metadata and path resolution results when they are used in high-frequency UI paths like list rendering.

## 2026-05-29 - [Pre-grouping large lists for rendering]
**Learning:** In SwiftUI, performing filtering or searching operations within a `ForEach` loop (especially when nested) results in O(N*C) complexity, where N is the total number of items and C is the number of groups/categories. Pre-calculating a dictionary of grouped items before the view body reduces this to O(N+C) and significantly improves scrolling performance.
**Action:** Always group large data sets into dictionaries or pre-filtered arrays before iterating over groups in SwiftUI views.
