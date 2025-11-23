# Project Overview

* macOS SwiftUI app that monitors clipboard, augments items with AI, and provides smart paste assistance. Uses SwiftData for persistence and optional local embeddings for semantic search.

# Architecture Summary

* Entry point: `Clippy/ClippyApp.swift:3` creates a `ModelContainer` and renders `ContentView`.

* Main UI: `Clippy/ContentView.swift:44` drives navigation and orchestrates services: `ClipboardMonitor`, `EmbeddingService`, `HotkeyManager`, `VisionScreenParser`, `TextCaptureService`, `FloatingDogWindowController`.

* Data model: `Clippy/Item.swift:4` stores clipboard items, tags, favorites, vector id and image path.

* Clipboard capture: `Clippy/ClipboardMonitor.swift:22` polls pasteboard, saves text/images, dedupes, assigns `vectorId`, calls AI for tags, and persists via SwiftData; image flow converts to PNG and saves under App Support.

* AI services: `Clippy/OpenAIService.swift` (cloud; Responses API for answers/tags, Chat Completions for vision) and `Clippy/LocalAIService.swift` (local endpoint; Qwen). Selection is persisted via UserDefaults in `ContentView`.

* Embeddings: `Clippy/EmbeddingService.swift` integrates Vectura MLX; currently disabled via `isEnabled = false`. `SuggestionEngine` falls back to heuristic ranking when embeddings disabled.

* Hotkeys: `Clippy/HotkeyManager.swift` listens for Option+X (text capture), Option+V (vision), Option+S (legacy suggestions).

* Text capture and injection: `Clippy/TextCaptureService.swift` captures typed characters and replaces them with the AI answer using CGEvent bulk injection, with AX fallback components and deletion of captured text length.

* Vision OCR: `Clippy/VisionScreenParser.swift` builds structured text using Vision; ScreenCaptureKit is a placeholder; currently generates a synthetic test image.

* Assistant UI: `Clippy/FloatingDogWindowController.swift` shows animated dog GIFs and a message bubble; attempts to position near caret using AX, but currently centers in top-right.

* List and detail UI: `Clippy/ClipboardListView.swift`, `Clippy/ClipboardItemRow.swift`, `Clippy/ClipboardDetailView.swift` provide browsing, tagging, copying, and deletion; deletion also removes embeddings.

* Suggestions overlay (unused in main flow): `Clippy/SuggestionsOverlay.swift` renders a floating window of ranked items and keyboard navigation.

* Assets and animation: `Clippy/ClippyGifPlayer.swift` for GIFs; `Clippy/ClippySpriteView.swift` with `agent.js` and `map.png` for sprite sheet animations.

# Build & Config

* Xcode project: `Clippy.xcodeproj/project.pbxproj`; `run.sh` builds and opens the app; verification scripts ensure “Clippy” naming.

* Entitlements: `Clippy/Clippy.entitlements` disables sandbox; Info plist includes Accessibility and Camera usage descriptions.

* SwiftPM dependencies: `Package.resolved` includes MLX, embeddings, HuggingFace transformers, VecturaKit.

# Observations & Risks

* Embeddings disabled; ranking relies on fallback scoring. If enabling embeddings, ensure model availability and performance.

* Local AI endpoint hardcoded to `http://10.0.0.138:1234` in `LocalAIService.swift:55`; should be configurable and default-off.

* ScreenCaptureKit not implemented; current Vision flow uses synthetic image; permission flows for screen recording needed.

* Floating assistant positioning computes caret frame but then centers the window; not actually near caret.

* Deleting items does not remove on-disk images; `ClipboardService.deleteItem` only deletes embeddings and the model item.

* OpenAI service uses `gpt-5` in Responses API; verify current availability; robust error handling exists but model selection should be configurable.

* API key storage uses UserDefaults; sensitive keys are better in Keychain.

* Accessibility permissions are required for event taps and AX; the app handles permission status and prompts but should degrade gracefully.

# Proposed Improvements

## Enable and Configure AI/Embeddings

* Add a Settings section to configure Local AI endpoint and model; default to environment variables; disable by default.

* Add a toggle to enable embeddings with clear status text; initialize `EmbeddingService` only when enabled.

## Real Screen OCR

* Implement ScreenCaptureKit-based capture of screen or window region; wire Option+V to capture and process text; store parsed text as items.

## Assistant Positioning

* Use caret bounds from AX to position dog window near active text input instead of top-right. Handle multi-display and bounds clamping.

## OpenAI Model Configuration

* Make model names selectable and validate availability; unify JSON output parsing for paste-image and answer cases.

## Robust Deletion

* When deleting image items, remove the saved file from `Application Support/Clippy/Images`.

## Key Management

* Migrate API key storage to Keychain; keep UserDefaults as fallback in dev builds.

## Suggestion Overlay Integration

* Provide a binding to show `SuggestionsWindowController` on a hotkey for ranked items, or remove if superseded by TextCapture.

## Logging and Privacy

* Gate verbose `print` logs behind a debug flag; avoid logging full content by default.

## Tests

* Add unit tests for tag parsing, Local AI response cleaning, dedup logic, and deletion of images; add integration test stubs for Vision capture.

# Implementation Steps

1. Settings: add fields for Local AI endpoint/model and an embeddings toggle; persist in UserDefaults.
2. Embeddings: honor toggle; initialize `EmbeddingService` only when enabled; surface status in UI.
3. OCR: implement ScreenCaptureKit capture pipeline; process with Vision; insert items; permission prompt flow.
4. Positioning: update `positionWindow` to use `getActiveTextInputFrame` and clamp to visible frame.
5. Deletion: delete image files on `ClipboardService.deleteItem` when `contentType == "image"` and `imagePath` is set.
6. OpenAI: parameterize model names; validate Responses API output; strengthen error handling.
7. Keychain: add simple wrapper to store/retrieve API key securely; keep existing binding.
8. Overlay: decide integration or removal; if integrating, add an Option-based hotkey path.
9. Logging: add `isDebugLoggingEnabled` flag to guard logs.
10. Tests: add Swift script/unit tests and run via CI or manual scripts.

# Verification Plan

* Manual: build via `run.sh`, exercise hotkeys, screen capture, text replacement, image paste.

* Automated: run verification scripts; add test scripts to validate Local AI parsing and deletion behavior; confirm no crashes and permissions flows.

# Deliverables

* Updated Swift files with settings, embeddings toggle, ScreenCaptureKit capture, corrected positioning, secure key storage, and deletion logic; new tests and optional overlay integration.

