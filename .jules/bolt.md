## 2025-05-26 - [Thread-safe lazy caching in Swift]
**Learning:** In Swift, `static let` properties are thread-safe and lazily initialized by default. Using them for caching expensive operations like directory listings is more efficient and safer than manually managing a `static var` with null checks, especially within SwiftUI view methods like `body` which can be called frequently and potentially from different threads.
**Action:** Use `static let` for one-time initialization of expensive caches to ensure thread safety and avoid redundant checks.
