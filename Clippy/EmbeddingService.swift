import Foundation
import SwiftData
import VecturaMLXKit
import VecturaKit
import MLXEmbedders

@MainActor
class EmbeddingService: ObservableObject {
    @Published var isInitialized = false
    @Published var statusMessage = "Initializing embedding service..."
    
    private var vectorDB: VecturaMLXKit?
    
    // MARK: - Feature Flag
    // Set to false to disable embedding functionality (for testing/development)
    private let isEnabled = false
    
    func initialize() async {
        // DISABLED: Embedding service is temporarily disabled
        guard isEnabled else {
            print("⏸️ [EmbeddingService] Disabled - skipping initialization")
            statusMessage = "Disabled (not in use)"
            return
        }
        
        print("🚀 [EmbeddingService] Initializing...")
        do {
            let config = VecturaConfig(
                name: "pastepup-clipboard",
                dimension: nil as Int? // Auto-detect from model
            )
            
            vectorDB = try await VecturaMLXKit(
                config: config,
                modelConfiguration: .qwen3_embedding
            )
             
            isInitialized = true
            statusMessage = "Ready (Qwen3-Embedding-0.6B)"
            print("✅ [EmbeddingService] Initialized successfully with Qwen3")
        } catch {
            statusMessage = "Failed to initialize: \(error.localizedDescription)"
            print("❌ [EmbeddingService] Initialization error: \(error)")
        }
    }
    
    func addDocument(vectorId: UUID, text: String) async {
        // DISABLED: Embedding service is temporarily disabled
        guard isEnabled else { return }
        
        guard let vectorDB = vectorDB else { 
            print("⚠️ [EmbeddingService] Cannot add document - vectorDB not initialized")
            return 
        }
        
        print("📝 [EmbeddingService] Adding document: \(text.prefix(50))...")
        
        do {
            _ = try await vectorDB.addDocuments(
                texts: [text],
                ids: [vectorId]
            )
            print("   ✅ Document added with ID: \(vectorId)")
        } catch {
            print("   ❌ Failed to add document: \(error)")
        }
    }
    
    func search(query: String, limit: Int = 10) async -> [(UUID, Float)] {
        // DISABLED: Embedding service is temporarily disabled
        guard isEnabled else { return [] }
        
        guard let vectorDB = vectorDB else { 
            print("⚠️ [EmbeddingService] Cannot search - vectorDB not initialized")
            return [] 
        }
        
        print("🔎 [EmbeddingService] Searching for: '\(query)' (limit: \(limit))")
        
        do {
            let results = try await vectorDB.search(
                query: query,
                numResults: limit,
                threshold: nil // No threshold, we'll rank ourselves
            )
            
            print("   ✅ Found \(results.count) results")
            for (index, result) in results.prefix(5).enumerated() {
                print("      \(index + 1). ID: \(result.id), Score: \(String(format: "%.3f", result.score))")
            }
            
            return results.map { ($0.id, $0.score) }
        } catch {
            print("   ❌ Search error: \(error)")
            return []
        }
    }
    
    func deleteDocument(vectorId: UUID) {
        // DISABLED: Embedding service is temporarily disabled
        guard isEnabled else { return }
        
        guard let vectorDB = vectorDB else { return }
        
        Task {
            do {
                try await vectorDB.deleteDocuments(ids: [vectorId])
            } catch {
                print("Failed to delete document: \(error)")
            }
        }
    }
}

