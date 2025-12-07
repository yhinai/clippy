import Foundation

@MainActor
class GrokService: ObservableObject, AIServiceProtocol {
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var lastErrorMessage: String?
    
    private var apiKey: String
    private let baseURL = "https://api.x.ai/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func updateApiKey(_ key: String) {
        self.apiKey = key
    }
    
    var hasValidAPIKey: Bool {
        !apiKey.isEmpty
    }
    
    // MARK: - AIServiceProtocol
    
    func generateAnswer(question: String, clipboardContext: [RAGContextItem], appName: String?) async -> String? {
        print("🤖 [GrokService] Generating answer...")
        isProcessing = true
        defer { isProcessing = false }
        
        // Use Reasoning model for answers as they involve context integration
        let model = GrokModelType.fastReasoning
        
        // Build Prompt
        let contextText = clipboardContext.isEmpty ? "No context available." : clipboardContext.enumerated().map { index, item in
            "[\(index + 1)] (App: \(item.title ?? "Unknown"))\n\(item.content)"
        }.joined(separator: "\n\n")
        
        let systemPrompt = """
        You are Clippy, a helpful macOS assistant. Answer the user's question based on the provided clipboard context.
        If the answer is not in the context, say so. Be concise and direct.
        """
        
        let userPrompt = """
        Context:
        \(contextText)
        
        Current App: \(appName ?? "Unknown")
        User Question: \(question)
        """
        
        let messages = [
            GrokMessage(role: "system", content: systemPrompt),
            GrokMessage(role: "user", content: userPrompt)
        ]
        
        return await callGrok(messages: messages, model: model)
    }
    
    func generateTags(content: String, appName: String?, context: String?) async -> [String] {
        print("🏷️ [GrokService] Generating tags...")
        isProcessing = true
        defer { isProcessing = false }
        
        // Use Fast Non-Reasoning model for simple tagging
        let model = GrokModelType.fastNonReasoning
        
        let prompt = """
        Analyze this text and generate 3-5 semantic tags.
        Content: \(content.prefix(500))
        App: \(appName ?? "Unknown")
        
        Return ONLY a JSON array of strings. Example: ["code", "swift", "ui"]
        """
        
        let messages = [
            GrokMessage(role: "user", content: prompt)
        ]
        
        guard let response = await callGrok(messages: messages, model: model) else { return [] }
        
        // Parse JSON
        let cleanJson = response.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let data = cleanJson.data(using: .utf8),
           let tags = try? JSONDecoder().decode([String].self, from: data) {
            return tags
        }
        
        return []
    }
    
    func analyzeImage(imageData: Data) async -> String? {
        // Grok Vision is needed here.
        // Currently probing showed grok-2-vision works.
        // But for the purpose of "Grok Latest Models" plan, we focus on text.
        // If needed, we can implement vision call similar to probe_grok.py
        return nil // Placeholder as the primary request was about the text models
    }
    
    // MARK: - Private API Call
    
    private func callGrok(messages: [GrokMessage], model: GrokModelType) async -> String? {
        guard !apiKey.isEmpty else {
            lastErrorMessage = "Grok API Key missing"
            return nil
        }
        
        guard let url = URL(string: baseURL) else { return nil }
        
        let requestBody = GrokRequest(
            model: model.rawValue,
            messages: messages,
            stream: false,
            temperature: 0.7
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
                print("❌ Grok API Error: \(errorMsg)")
                lastError = errorMsg
                return nil
            }
            
            let grokResponse = try JSONDecoder().decode(GrokResponse.self, from: data)
            return grokResponse.choices.first?.message.content
            
        } catch {
            print("❌ Grok Network Error: \(error)")
            lastError = error.localizedDescription
            return nil
        }
    }
}
