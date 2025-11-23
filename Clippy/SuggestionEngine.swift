import Foundation
import SwiftData

@MainActor
class SuggestionEngine: ObservableObject {
    @Published var suggestions: [Item] = []
    @Published var isSearching = false
    
    func getSuggestions(
        context: String,
        currentApp: String,
        items: [Item],
        embeddingService: EmbeddingService,
        userPrompt: String? = nil
    ) async {
        print("🔍 [SuggestionEngine] Starting search...")
        print("   Context: \(context)")
        print("   Current App: \(currentApp)")
        print("   User Prompt: \(userPrompt ?? "None")")
        print("   Total items available: \(items.count)")
        print("   Items with vectorIds: \(items.filter { $0.vectorId != nil }.count)")
        print("   Items with tags: \(items.filter { !$0.tags.isEmpty }.count)")
        
        isSearching = true
        defer { isSearching = false }
        
        // Enhance query with user prompt and app context for better embedding search
        let enhancedQuery = buildEnhancedQuery(context: context, currentApp: currentApp, userPrompt: userPrompt)
        
        // Get vector similarity scores (keyed by vectorId UUID)
        let vectorResults = await embeddingService.search(query: enhancedQuery, limit: 20)
        print("   Vector search returned: \(vectorResults.count) results")
        let vectorScores = Dictionary(uniqueKeysWithValues: vectorResults)
        
        // Check if embeddings are disabled (no results means disabled)
        let embeddingsEnabled = !vectorResults.isEmpty || items.isEmpty
        if !embeddingsEnabled {
            print("   ℹ️ Embeddings disabled - using fallback ranking")
        }
        
        // Rank items
        let now = Date()
        let ranked = items.compactMap { item -> (Item, Double)? in
            // If embeddings are disabled, skip the vectorId check and use fallback scoring
            if !embeddingsEnabled {
                // Fallback: rank by recency, frequency, app match, and tag relevance only
                return rankItemWithoutEmbeddings(item: item, now: now, currentApp: currentApp, context: context)
            }
            
            guard let vid = item.vectorId, let vectorScore = vectorScores[vid] else { 
                if item.vectorId == nil {
                    print("   ⚠️ Item has no vectorId: \(item.content.prefix(50))")
                }
                return nil 
            }
            
            // Filter out empty or whitespace-only content
            let trimmedContent = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty {
                print("   ⚠️ Skipping empty content item")
                return nil
            }
            
            // Filter out extremely short content (likely noise)
            if trimmedContent.count < 3 {
                print("   ⚠️ Skipping very short content: \(trimmedContent)")
                return nil
            }
            
            // Normalize vector score (clamp to 0-1 range)
            let normalizedVectorScore = min(max(Double(vectorScore), 0.0), 1.0)
            
            // Check for abnormal scores
            if Double(vectorScore) > 10.0 {
                print("   ⚠️ Abnormal vector score detected: \(vectorScore), normalized to: \(normalizedVectorScore)")
            }
            
            // Recency score (decay over 24 hours)
            let hoursAgo = now.timeIntervalSince(item.timestamp) / 3600
            let recencyScore = exp(-hoursAgo / 24.0)
            
            // Frequency score (normalized)
            let frequencyScore = min(Double(item.usageCount) / 10.0, 1.0)
            
            // App match bonus
            let appBonus = (item.appName == currentApp) ? 0.1 : 0.0
            
            // Tag relevance bonus
            let tagBonus = calculateTagRelevance(item: item, currentApp: currentApp, context: context)
            
            // Combined score using normalized vector score
            // Increased tag weight since they're semantically rich
            let finalScore = (normalizedVectorScore * 0.5) + (recencyScore * 0.15) + (frequencyScore * 0.1) + appBonus + (tagBonus * 0.15)
            
            print("   📊 Item score: \(String(format: "%.3f", finalScore)) (tags: \(item.tags.prefix(3))) - \(trimmedContent.prefix(40))...")
            
            return (item, finalScore)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map { $0.0 }
        
        suggestions = ranked
        
        if ranked.isEmpty && !items.isEmpty {
            print("   ⚠️ No valid suggestions after filtering! All items were empty or invalid.")
        }
        print("✅ [SuggestionEngine] Final suggestions: \(suggestions.count)")
        for (index, suggestion) in suggestions.enumerated() {
            print("   \(index + 1). \(suggestion.content.prefix(60))...")
        }
    }
    
    func clearSuggestions() {
        suggestions = []
    }
    
    // MARK: - Helper Methods
    
    private func buildEnhancedQuery(context: String, currentApp: String, userPrompt: String?) -> String {
        // Enhance the query with user prompt, app context to help embedding search
        var parts: [String] = []
        
        // Prioritize user prompt if available
        if let prompt = userPrompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(prompt)
        }
        
        // Add context if no user prompt or to supplement it
        if !context.isEmpty {
            parts.append(context)
        }
        
        // Add app name for context
        if !currentApp.isEmpty && currentApp != "Unknown" {
            parts.append("in \(currentApp)")
        }
        
        return parts.joined(separator: " ")
    }
    
    private func calculateTagRelevance(item: Item, currentApp: String, context: String) -> Double {
        guard !item.tags.isEmpty else { return 0.0 }
        
        var relevance = 0.0
        let contextLower = context.lowercased()
        let appLower = currentApp.lowercased()
        
        for tag in item.tags {
            let tagLower = tag.lowercased()
            
            // Exact match in context
            if contextLower.contains(tagLower) {
                relevance += 0.3
            }
            
            // App name match
            if appLower.contains(tagLower) || tagLower.contains(appLower) {
                relevance += 0.25
            }
            
            // Common domain tags (give slight boost for likely relevant domains)
            let commonDomainTags = ["code", "terminal", "python", "swift", "javascript", "error", "debugging"]
            if commonDomainTags.contains(tagLower) {
                relevance += 0.05
            }
        }
        
        // Normalize to 0-1 range
        return min(relevance, 1.0)
    }
    
    private func rankItemWithoutEmbeddings(item: Item, now: Date, currentApp: String, context: String) -> (Item, Double)? {
        // Filter out empty or whitespace-only content
        let trimmedContent = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty {
            print("   ⚠️ Skipping empty content item")
            return nil
        }
        
        // Filter out extremely short content (likely noise)
        if trimmedContent.count < 3 {
            print("   ⚠️ Skipping very short content: \(trimmedContent)")
            return nil
        }
        
        // Simple text matching score (for context relevance)
        let contextRelevance = calculateSimpleTextMatch(itemContent: trimmedContent, context: context)
        
        // Recency score (decay over 24 hours)
        let hoursAgo = now.timeIntervalSince(item.timestamp) / 3600
        let recencyScore = exp(-hoursAgo / 24.0)
        
        // Frequency score (normalized)
        let frequencyScore = min(Double(item.usageCount) / 10.0, 1.0)
        
        // App match bonus
        let appBonus = (item.appName == currentApp) ? 0.2 : 0.0
        
        // Tag relevance bonus
        let tagBonus = calculateTagRelevance(item: item, currentApp: currentApp, context: context)
        
        // Combined score without embeddings (weight more heavily on recency, frequency, and app match)
        let finalScore = (contextRelevance * 0.3) + (recencyScore * 0.25) + (frequencyScore * 0.15) + appBonus + (tagBonus * 0.1)
        
        print("   📊 Item score (no embeddings): \(String(format: "%.3f", finalScore)) - \(trimmedContent.prefix(40))...")
        
        return (item, finalScore)
    }
    
    private func calculateSimpleTextMatch(itemContent: String, context: String) -> Double {
        guard !context.isEmpty else { return 0.5 } // Neutral score when no context
        
        let contentLower = itemContent.lowercased()
        let contextLower = context.lowercased()
        
        // Split context into words
        let contextWords = contextLower.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard !contextWords.isEmpty else { return 0.5 }
        
        // Count how many context words appear in the item content
        let matchingWords = contextWords.filter { word in
            contentLower.contains(word)
        }
        
        // Simple ratio of matching words
        return Double(matchingWords.count) / Double(contextWords.count)
    }
}

