# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-05-25

### Added
- **Ask AI**: A new feature to get AI-powered insights about Homebrew packages. Supports multiple backends:
  - Apple Intelligence (on-device)
  - OpenRouter
  - Gemini
  - Ollama (local)
- **AI Recommendations**: Personalized package suggestions based on your installed apps.
- **Featured Apps**: A curated section of popular macOS applications.
- **Category Hiding**: Users can now hide categories they are not interested in.
- **Multi-threaded Terminal**: Improved the console to handle multiple concurrent Homebrew operations across different "Thread Lanes".
- **Liquid Glass UI**: Enhanced the visual aesthetic with more refined SwiftUI materials and animations.

### Changed
- **Minimum macOS Version**: Standardized the minimum required version to macOS 14.0 (Sonoma).
- **Project Structure**: Improved build script to use relative paths and handle app icons more reliably.

### Fixed
- Hardcoded system paths in source code and build scripts have been replaced with dynamic and relative paths for better portability.
- Improved version comparison logic for detecting package updates.
