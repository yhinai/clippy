#!/usr/bin/env swift

import Foundation

// MARK: - Response Models
struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

// MARK: - Image Analysis Function
func analyzeImage(imagePath: String, apiKey: String) async throws -> String {
    // Read image file
    let expandedPath = NSString(string: imagePath).expandingTildeInPath
    let imageURL = URL(fileURLWithPath: expandedPath)
    
    guard FileManager.default.fileExists(atPath: expandedPath) else {
        throw NSError(domain: "ImageAnalysis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image file not found at: \(expandedPath)"])
    }
    
    let imageData = try Data(contentsOf: imageURL)
    let base64Image = imageData.base64EncodedString()
    
    print("✓ Image loaded: \(expandedPath)")
    print("✓ Image size: \(imageData.count) bytes")
    print("✓ Base64 length: \(base64Image.count) characters")
    print("\nSending request to OpenAI...\n")
    
    // Prepare the request
    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    
    // Build the request body
    let requestBody: [String: Any] = [
        "model": "gpt-4.1",
        "messages": [
            [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": "give quick summary of it."
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/png;base64,\(base64Image)"
                        ]
                    ]
                ]
            ]
        ],
        "max_tokens": 500
    ]
    
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    // Make the request
    let (data, response) = try await URLSession.shared.data(for: request)
    
    // Check response
    guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "ImageAnalysis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }
    
    guard httpResponse.statusCode == 200 else {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "ImageAnalysis", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorMessage)"])
    }
    
    // Parse response
    let decoder = JSONDecoder()
    let openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
    
    guard let firstChoice = openAIResponse.choices.first else {
        throw NSError(domain: "ImageAnalysis", code: 3, userInfo: [NSLocalizedDescriptionKey: "No response content"])
    }
    
    return firstChoice.message.content
}

// Helper to repeat strings
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// MARK: - Main Execution
print("=== OpenAI Vision API - Image Analysis Test ===\n")

// Get API key from environment
guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
    print("❌ Error: OPENAI_API_KEY environment variable not set")
    print("\nPlease set it using:")
    print("export OPENAI_API_KEY='your-api-key-here'")
    exit(1)
}

// Image path
let imagePath = "~/Desktop/test.png"

// Run async task
Task {
    do {
        let summary = try await analyzeImage(imagePath: imagePath, apiKey: apiKey)
        
        print("=" * 60)
        print("ANALYSIS RESULT:")
        print("=" * 60)
        print(summary)
        print("=" * 60)
        
        exit(0)
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Keep the script running until the async task completes
RunLoop.main.run()

