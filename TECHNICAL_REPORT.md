# Technical Report: Clippy

## 1. Executive Summary
Clippy (formerly PastePup) is a macOS clipboard manager leveraging local and cloud AI to provide intelligent context-aware suggestions and semantic search. It uses `SwiftData` for persistence, `VecturaKit` for embeddings, and Accessibility APIs for context gathering.

## 2. System Architecture

### Core Components
- **ClipboardMonitor**: The central engine that monitors the system pasteboard. It uses `NSPasteboard` polling and Accessibility APIs (`AXUIElement`) to capture content and context (active window, selected text).
- **Data Layer (SwiftData)**: The `Item` model stores clipboard history, including timestamp, content type (text/image), app source, and vector embeddings.
- **AI Services**:
  - `OpenAIService`: Interfaces with OpenAI's API for semantic tagging and question answering (GPT-4/5).
  - `LocalAIService`: Interfaces with a local LLM (e.g., Qwen via local endpoint) for privacy-focused operations.
- **SuggestionEngine**: Ranks clipboard items based on vector similarity (embeddings), recency, and frequency.
- **UI Layer (SwiftUI)**: `ContentView` is the main interface. `FloatingDogWindowController` manages the "Clippy-like" floating assistant.

### Data Flow
1.  **Capture**: `ClipboardMonitor` detects changes -> Captures content -> Captures Context (AX).
2.  **Process**: Content is passed to `OpenAIService` or `LocalAIService` for tagging.
3.  **Store**: `Item` is saved to `SwiftData`. Embeddings are generated and stored via `EmbeddingService`.
4.  **Retrieval**: User query -> `SuggestionEngine` searches embeddings -> Returns ranked `Item` list.

## 3. Build Analysis (Post-Refactor)
- **Project File**: `Clippy.xcodeproj`
- **Targets**: `Clippy` (macOS App)
- **Bundle Identifier**: `altic.Clippy`
- **Dependencies**:
  - `VecturaKit`: Vector database/search.
  - `VecturaMLXKit`: Machine learning extensions.
- **Build Configuration**:
  - Minimum Deployment Target: macOS 15.0
  - Swift Version: 5.0

## 4. Refactor Execution (PastePup → Clippy)

### Changes Implemented
- **Project Name**: Renamed `PastePup.xcodeproj` to `Clippy.xcodeproj`.
- **Bundle ID**: Updated to `altic.Clippy`.
- **Root Directory**: Renamed `PastePup/` to `Clippy/`.
- **Main App File**: Renamed `PastePupApp.swift` to `ClippyApp.swift` and updated the `@main` struct to `ClippyApp`.
- **UI Strings**: All user-facing text (e.g., "PastePup is listening...") now reads "Clippy...".
- **Configuration**: `Info.plist` and `project.pbxproj` updated to reflect new paths and names.

### Verification
A verification script (`scripts/verify_integrity.py`) was executed to ensure:
1.  No "PastePup" strings remain in source code or filenames.
2.  Critical project settings (Product Name, Bundle ID) match the new "Clippy" identity.
3.  The file structure is consistent with the Xcode project references.
