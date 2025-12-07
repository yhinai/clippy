# Grok Latest Models Integration Plan

## 🚀 Overview
This plan outlines the integration of the latest Grok models (`grok-4-1-fast-reasoning` and `grok-4-1-fast-non-reasoning`) into the Clippy architecture. These models offer a powerful combination of speed and reasoning capabilities, enabling "Clippy" to act as a true cognitive prosthetic.

## 🤖 Model Strategy

### 1. `grok-4-1-fast-reasoning`
*   **Role:** The "Cortex" / Deep Thinking Engine.
*   **Use Cases:**
    *   **Complex Intent Classification:** Deciding if a user query needs a tool, a memory search, or a simple chat response.
    *   **Memory Consolidation (Reflector):** Analyzing daily logs to update "Core Memory" (Persona and User profiles).
    *   **Multi-Step Planning:** "Find the last email from John and create a Jira ticket based on it."
    *   **Code Generation:** When the user asks for complex Swift/Python implementations.
*   **Configuration:**
    *   Context Window: 2,000,000 tokens (assumed based on specs).
    *   Cost: ~$0.20/1M input (Low cost allows for rich context injection).

### 2. `grok-4-1-fast-non-reasoning`
*   **Role:** The "Reflex" / Fast Chat Engine.
*   **Use Cases:**
    *   **Real-time Conversation:** Low-latency chat for casual interaction.
    *   **Simple Summarization:** Summarizing clipboard items for the vector DB.
    *   **UI Micro-interactions:** Generating quick witty remarks or status updates.
*   **Configuration:**
    *   Optimized for TPM (4M) and RPM (480).

## 🏗️ Architectural Updates

### 1. `GrokService.swift` (Swift Layer)
The `GrokService` must be updated to support dynamic model selection based on task complexity.

```swift
enum GrokModelType {
    case fastReasoning    // grok-4-1-fast-reasoning
    case fastNonReasoning // grok-4-1-fast-non-reasoning
}

func sendMessage(_ text: String, context: [ContextItem], model: GrokModelType = .fastNonReasoning) async -> String
```

### 2. Memory System (Letta/Sidecar Layer)
The Python sidecar (if used for Letta) will be configured to route "System 2" (thinking) tasks to the reasoning model.

*   **Archival Search:** Uses `reasoning` model to re-rank results.
*   **Core Memory Update:** Uses `reasoning` model to decide *what* to write to the permanent user profile.

## 📋 Implementation Steps

1.  **Update API Configuration:**
    *   Add `grok-4-1-fast-reasoning` and `grok-4-1-fast-non-reasoning` to `Models.swift` or `GrokService` configuration.
2.  **Smart Router Implementation:**
    *   Create a lightweight classifier (or use the non-reasoning model) to determine if a query requires the "Reasoning" model.
    *   *Heuristic:* If query contains "plan", "analyze", "code", or "search history", use `reasoning`. Else use `non-reasoning`.
3.  **Reflector Agent:**
    *   Implement a background job that uses `grok-4-1-fast-reasoning` to digest the day's `clipboard_memory` and update the `User` model.

## 💰 Cost & Performance Analysis
*   **High TPM Limit (4M):** Allows us to stuff the context window with massive amounts of clipboard history for RAG without hitting rate limits.
*   **Low Cost:** Enables "always-on" intelligence rather than rationing usage.

---
**Next Actions:**
1.  Initialize `GrokService.swift` with these models.
2.  Update `GROK_JARVIS_PLAN.md` to reflect these specific models.
