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
    
    private let endpoint: String
    private let model: String
    
    // Default configuration
    private static let defaultEndpoint = "http://localhost:8080/v1/chat/completions"
    private static let defaultModel = "mlx-community/Qwen3-4B-Thinking-2507-4bit"
    
    init(endpoint: String = LocalAIService.defaultEndpoint, model: String = LocalAIService.defaultModel) {
        self.endpoint = endpoint
        self.model = model
    }
    
    /// Generate an answer based on user question and clipboard context
    func generateAnswer(
        question: String,
        clipboardContext: [(content: String, tags: [String])],
        appName: String?
    ) async -> String? {
        print("🤖 [LocalAIService] Generating answer...")
        print("   Question: \(question)")
        print("   Clipboard items: \(clipboardContext.count)")
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Build the prompt
        let prompt = buildAnswerPrompt(question: question, clipboardContext: clipboardContext, appName: appName)
        
        // Make API call
        guard let answer = await callLocalAIForAnswer(prompt: prompt) else {
            print("   ❌ Failed to generate answer")
            return nil
        }
        
        print("   ✅ Generated answer: \(answer.prefix(100))...")
        return answer
    }
    
    /// Generate semantic tags for clipboard content to improve retrieval
    /// Returns tags like: ["terminal", "python", "code", "error_message"]
    func generateTags(
        content: String,
        appName: String?,
        context: String?
    ) async -> [String] {
        print("🏷️  [LocalAIService] Generating tags...")
        print("   Content: \(content.prefix(100))...")
        print("   App: \(appName ?? "Unknown")")
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Build the prompt
        let prompt = buildTaggingPrompt(content: content, appName: appName, context: context)
        
        // Make API call
        guard let tags = await callLocalAI(prompt: prompt) else {
            print("   ❌ Failed to generate tags")
            return []
        }
        
        print("   ✅ Generated tags: \(tags)")
        return tags
    }
    
    private func buildAnswerPrompt(question: String, clipboardContext: [(content: String, tags: [String])], appName: String?) -> String {
        let contextText: String
        if clipboardContext.isEmpty {
            contextText = "No clipboard context available."
        } else {
            contextText = clipboardContext.enumerated().map { index, item in
                let tagsText = item.tags.isEmpty ? "" : " [Tags: \(item.tags.joined(separator: ", "))]"
                return "[\(index + 1)]\(tagsText)\n\(item.content)"
            }.joined(separator: "\n\n---\n\n")
        }
        
        let prompt = """
        Context:
        \(contextText)
        
        Question: \(question)
        """
        
        return prompt
    }
    
    private func buildTaggingPrompt(content: String, appName: String?, context: String?) -> String {
        // Get time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = switch hour {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<22: "evening"
        default: "night"
        }
        
        let prompt = """
        App: \(appName ?? "Unknown")
        Time: \(timeOfDay)
        Content: \(content.prefix(500))
        
        Generate 3-7 semantic tags for this clipboard item. Focus on content type, domain, and key topics. /no_think
        
        Return output in the form of JSON:
        {
          "tags": ["tag1", "tag2", "tag3"]
        }
        
        Return ONLY the JSON, nothing else. No explanations, no additional text.
        """
        
        return prompt
    }
    
    private func callLocalAIForAnswer(prompt: String) async -> String? {
        guard let url = URL(string: endpoint) else {
            lastError = "Invalid URL"
            return nil
        }
        
        print("   📤 Sending prompt to LocalAI for answer:")
        print("   \(prompt)")
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are Clippy, an intelligent clipboard assistant. Analyze the clipboard context deeply to answer the user's question. Return ONLY a JSON object with the answer in the 'A' field."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7,
            "max_tokens": 2048,
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Print request body for debugging
            if let requestJSON = try? JSONSerialization.data(withJSONObject: requestBody),
               let requestString = String(data: requestJSON, encoding: .utf8) {
                print("   📤 Request Body: \(requestString)")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return nil
            }
            
            print("   📡 LocalAI Response Status: \(httpResponse.statusCode)")
            
            // Print raw response for debugging
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("   📄 Raw Response: \(rawResponse)")
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                lastError = "API Error (\(httpResponse.statusCode)): \(errorMessage)"
                print("   ❌ API Error: \(errorMessage)")
                return nil
            }
            
            // Parse response
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(LocalAIResponse.self, from: data)
            
            // Extract content from response
            guard let choices = apiResponse.choices,
                  let firstChoice = choices.first,
                  let message = firstChoice.message,
                  let content = message.content else {
                lastError = "No content in response"
                print("   ❌ No content found in response")
                return nil
            }
            
            print("   📝 Extracted content: \(content)")
            
            // Clean the content by removing <think> tags and extracting JSON
            let cleanedContent = cleanLocalAIResponse(content)
            print("   🧹 Cleaned content: \(cleanedContent)")
            
            // Parse the JSON to extract the answer from "A" field
            if let jsonData = cleanedContent.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let answer = jsonObject["A"] as? String {
                let cleanAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                print("   ✅ Parsed answer: \(cleanAnswer.prefix(200))...")
                return cleanAnswer
            }
            
            // Fallback if JSON parsing fails - return raw content
            print("   ⚠️ JSON parsing failed, returning raw content")
            return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            lastError = error.localizedDescription
            print("   ❌ Error: \(error)")
            return nil
        }
    }
    
    private func callLocalAI(prompt: String) async -> [String]? {
        guard let url = URL(string: endpoint) else {
            lastError = "Invalid URL"
            return nil
        }
        
        print("   📤 Sending prompt to LocalAI for tagging:")
        print("   \(prompt)")
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.3,
            "max_tokens": 1024,
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Print request body for debugging
            if let requestJSON = try? JSONSerialization.data(withJSONObject: requestBody),
               let requestString = String(data: requestJSON, encoding: .utf8) {
                print("   📤 Request Body: \(requestString)")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return nil
            }
            
            print("   📡 LocalAI Response Status: \(httpResponse.statusCode)")
            
            // Print raw response for debugging
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("   📄 Raw Response: \(rawResponse)")
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                lastError = "API Error (\(httpResponse.statusCode)): \(errorMessage)"
                print("   ❌ API Error: \(errorMessage)")
                return nil
            }
            
            // Parse response
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(LocalAIResponse.self, from: data)
            
            // Extract tags from response
            guard let choices = apiResponse.choices,
                  let firstChoice = choices.first,
                  let message = firstChoice.message,
                  let content = message.content else {
                lastError = "No content in response"
                print("   ❌ No content found in response")
                return nil
            }
            
            print("   📝 Extracted content: \(content)")
            
            // Clean the content by removing <think> tags and extracting JSON
            let cleanedContent = cleanLocalAIResponse(content)
            print("   🧹 Cleaned content: \(cleanedContent)")
            
            // Try parsing as JSON first
            if let jsonData = cleanedContent.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let tagsArray = jsonObject["tags"] as? [String] {
                let tags = tagsArray.map { $0.lowercased() }.filter { !$0.isEmpty }
                print("   ✅ Parsed JSON tags: \(tags)")
                return tags
            }
            
            // Fallback to comma-separated parsing
            print("   ⚠️ JSON parsing failed, trying comma-separated format")
            let tags = cleanedContent
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            
            return tags
            
        } catch {
            lastError = error.localizedDescription
            print("   ❌ Error: \(error)")
            return nil
        }
    }
    
    /// Clean Local AI response by removing <think> tags and extracting JSON
    private func cleanLocalAIResponse(_ content: String) -> String {
        var cleaned = content
        
        // Remove <think>...</think> tags (including multiline)
        let thinkPattern = #"<think>.*?</think>"#
        cleaned = cleaned.replacingOccurrences(of: thinkPattern, with: "", options: [.regularExpression, .caseInsensitive])
        
        // Remove any remaining <think> tags without closing tags
        cleaned = cleaned.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        
        // Trim whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for JSON pattern { "A": "..." }
        if let jsonRange = cleaned.range(of: #"\{[^}]*"A"[^}]*\}"#, options: .regularExpression) {
            cleaned = String(cleaned[jsonRange])
        }
        
        return cleaned
    }
    
    /// Convenience method to create service with custom endpoint
    static func withEndpoint(_ endpoint: String, model: String = "qwen/qwen3-4b") -> LocalAIService {
        return LocalAIService(endpoint: endpoint, model: model)
    }
}
