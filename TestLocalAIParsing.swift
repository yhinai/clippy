#!/usr/bin/env swift

import Foundation

// Test the parsing logic
func cleanLocalAIResponse(_ content: String) -> String {
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

// Test cases
let testCases = [
    "<think>\nOkay, the user asked \"What is 2+2?\" Let me think about how to respond. Well, the question is straightforward. The answer is 4, right? But I should make sure to explain it clearly.\n\nWait, maybe they're looking for a more detailed explanation? Like why 2+2 is 4. But the question seems simple enough. I should just state the answer clearly. However, sometimes people might have different interpretations, but in basic arithmetic, 2+2 is definitely 4.\n\nI should check if there's any trick or context I'm missing. But the question is pretty straightforward. So the answer should be 4. Maybe add a friendly sentence to confirm that. Yeah, that's it.\n</think>\n\nThe sum of 2 and 2 is **4**.\n\nIn basic arithmetic, adding 2 and 2 results in 4. Let me know if you'd like further clarification! 😊",
    
    "<think>\nOkay, the user asked \"What is 2+2?\" Let me think about how to respond. Well, the question is straightforward. The answer is 4, right? But I should make sure to explain it clearly.\n</think>\n\n{\"A\": \"Hyatt Regency Coconut Point Resort and Spa\"}",
    
    "{\"A\": \"Hyatt Regency Coconut Point Resort and Spa\"}",
    
    "<think>\nSome reasoning here\n</think>\n\n{\"A\": \"Simple answer\"}",
    
    "Random text before {\"A\": \"Answer in JSON\"} and after"
]

print("🧪 Testing Local AI Response Parsing")
print("═══════════════════════════════════════")

for (index, testCase) in testCases.enumerated() {
    print("\n📝 Test Case \(index + 1):")
    print("Input: \(testCase.prefix(100))...")
    
    let cleaned = cleanLocalAIResponse(testCase)
    print("Cleaned: \(cleaned)")
    
    // Try to parse JSON
    if let jsonData = cleaned.data(using: .utf8),
       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let answer = jsonObject["A"] as? String {
        print("✅ Parsed answer: '\(answer)'")
    } else {
        print("❌ Failed to parse JSON")
    }
    
    print("─────────────────────────────────────")
}

print("\n✅ All tests completed!")
