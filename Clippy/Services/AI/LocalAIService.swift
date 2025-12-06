import Foundation

// Local AI API Response Structure
struct LocalAIResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
    let usage: Usage?
    
    struct Choice: Codable {
        let index: Int?
        let message: Message?
        let delta: Delta?
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index, message, delta
            case finishReason = "finish_reason"
        }
    }
    
    struct Message: Codable {
        let role: String?
        let content: String?
    }
    
    struct Delta: Codable {
        let role: String?
        let content: String?
    }
    
    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

@MainActor
class LocalAIService: ObservableObject {
    @Published var isProcessing = false
    @Published var lastError: String?
    
    // Endpoints configuration
    private let visionEndpoint = "http://localhost:8081/chat/completions"
    private let ragEndpoint = "http://localhost:8082/v1/chat/completions"
    private let extractEndpoint = "http://localhost:8083/v1/chat/completions"
    
    // Models configuration
    private let visionModel = "mlx-community/LFM2-VL-3B-4bit"
    private let ragModel = "LiquidAI/LFM2-1.2B-RAG"
    private let extractModel = "LiquidAI/LFM2-1.2B-Extract"
    
    // Default configuration (kept for backward compatibility if needed)
    private let defaultEndpoint = "http://localhost:8082/v1/chat/completions"
    private let defaultModel = "LiquidAI/LFM2-1.2B-RAG"
    
    init() {}
    
    // MARK: - Vision (LFM2-VL-3B)
    
    /// Generate a description for an image using LFM2-VL-3B
    /// Generate a description for an image using LFM2-VL-3B
    func generateVisionDescription(base64Image: String, screenText: String? = nil) async -> String? {
        print("👁️ [LocalAIService] Generating vision description...")
        isProcessing = true
        defer { isProcessing = false }
        
        var prompt = """
        Analyze this screen content in high detail for future reference.
        """
        
        if let text = screenText, !text.isEmpty {
            prompt += "\n\nCONTEXT FROM SCREEN TEXT (Use this to verify details/code/filenames):\n\(text.prefix(2000))\n"
        }
        
        prompt += """
        
        STRICT OUTPUT FORMAT:
        Title: [Action/Topic] - [Key Subject]
        Files/Context:
        1. [File 1]
        2. [File 2]
        (List MAX 5 distinct files. STOP after 5.)

        Code:
        - [Description of visible code]
        - [Key variables/functions]

        Terminal:
        - [Last command]
        - [Output summary]

        Intent:
        - [User's likely goal]

        CONSTRAINTS:
        - OUTPUT MUST START DIRECTLY WITH "Title:".
        - DO NOT WRITE ANY PREAMBLE OR CONVERSATIONAL TEXT (e.g., "Here is the analysis...").
        - Files/Context: Max 5 items. ABSOLUTELY NO REPETITION.
        - Code/Terminal/Intent: Use bullet points.
        - STOP generating if you start repeating.
        """
        
        // Custom format for our vision server
        let requestBody: [String: Any] = [
            "model": visionModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 1024,
            "temperature": 0.7
        ]
        
        return await makeRequest(endpoint: visionEndpoint, body: requestBody, extractField: "content")
    }
    
    // MARK: - RAG (LFM2-1.2B-RAG)
    
    /// Generate an answer based on user question and clipboard context using LFM2-1.2B-RAG
    func generateAnswer(
        question: String,
        clipboardContext: [(content: String, tags: [String])],
        appName: String?
    ) async -> String? {
        print("🤖 [LocalAIService] Generating RAG answer...")
        isProcessing = true
        defer { isProcessing = false }
        
        let contextText = buildContextString(clipboardContext)
        let prompt = """
        Context:
        \(contextText)
        
        Question: \(question)
        
        Instructions:
        Answer the question accurately based on the Context.
        - If the user asks for a list (e.g., "all API keys"), list them clearly (e.g., Name=Value).
        - If the answer is found in the context, provide it exactly as it appears.
        - If the answer is NOT in the context, say "I couldn't find that information in your clipboard history."
        
        Answer:
        """
        
        let requestBody: [String: Any] = [
            "model": ragModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 256,
            "temperature": 0.3
        ]
        
        return await makeRequest(endpoint: ragEndpoint, body: requestBody, extractField: "content")
    }
    
    // MARK: - Extract (LFM2-1.2B-Extract)
    
    /// Extract structured data from text using LFM2-1.2B-Extract
    func extractStructuredData(text: String, schema: String) async -> String? {
        print("⛏️ [LocalAIService] Extracting data...")
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = "Extract the following information from the text. Return ONLY the requested data in the specified format. No conversational text.\nText: \"\(text)\"\nSchema: \(schema)"
        
        let requestBody: [String: Any] = [
            "model": extractModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 512,
            "temperature": 0.1
        ]
        
        return await makeRequest(endpoint: extractEndpoint, body: requestBody, extractField: "content")
    }
    
    // MARK: - Helper Methods
    
    private func buildContextString(_ clipboardContext: [(content: String, tags: [String])]) -> String {
        if clipboardContext.isEmpty { return "No context available." }
        return clipboardContext.enumerated().map { index, item in
            let tagsText = item.tags.isEmpty ? "" : " [Tags: \(item.tags.joined(separator: ", "))]"
            return "[\(index + 1)]\(tagsText)\n\(item.content)"
        }.joined(separator: "\n\n---\n\n")
    }
    
    private func makeRequest(endpoint: String, body: [String: Any], extractField: String) async -> String? {
        guard let url = URL(string: endpoint) else {
            lastError = "Invalid URL: \(endpoint)"
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ API Error (\(endpoint)): \(errorMessage)")
                lastError = "API Error: \(errorMessage)"
                return nil
            }
            
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(LocalAIResponse.self, from: data)
            
            if let content = apiResponse.choices?.first?.message?.content {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            return nil
            
        } catch {
            print("❌ Network Error: \(error)")
            lastError = error.localizedDescription
            return nil
        }
    }
    
    /// Compatibility method for existing code (Tagging) - uses RAG model for now
    func generateTags(content: String, appName: String?, context: String?) async -> [String] {
        // Simple implementation using RAG model for tagging
        let prompt = """
        Analyze this text and generate 3-5 concise keywords/tags.
        Rules:
        1. Return ONLY a comma-separated list (e.g. "Tag1, Tag2, Tag3").
        2. Do NOT use numbered lists.
        3. Do NOT write full sentences or introductions like "Here are the tags".
        
        Text: "\(content.prefix(500))"
        """
        
        guard let response = await generateAnswer(question: prompt, clipboardContext: [], appName: appName) else {
            return []
        }
        
        // Robust cleaning and parsing
        var cleanResponse = response
        
        // Remove common conversational prefixes
        let prefixesToRemove = ["Here are", "The tags are", "Keywords:", "Tags:"]
        for prefix in prefixesToRemove {
            if let range = cleanResponse.range(of: prefix, options: .caseInsensitive) {
                cleanResponse.removeSubrange(cleanResponse.startIndex..<range.upperBound)
            }
        }
        
        // Split by newlines or commas
        let separators = CharacterSet(charactersIn: ",\n")
        let rawTags = cleanResponse.components(separatedBy: separators)
        
        let tags = rawTags.compactMap { rawTag -> String? in
            // Clean up each tag (remove "1.", "- ", etc.)
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = trimmed
                .replacingOccurrences(of: "^[0-9]+\\.", with: "", options: .regularExpression) // Remove "1."
                .replacingOccurrences(of: "^- ", with: "", options: .regularExpression)        // Remove "- "
                .replacingOccurrences(of: "^• ", with: "", options: .regularExpression)        // Remove "• "
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return cleaned.isEmpty ? nil : cleaned
        }
        
        return Array(Set(tags)).prefix(5).sorted() // Dedupe and limit
    }
}
