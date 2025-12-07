import Foundation

struct GrokMessage: Codable, Identifiable {
    var id: UUID = UUID()
    let role: String
    let content: String
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

struct GrokRequest: Codable {
    let model: String
    let messages: [GrokMessage]
    let stream: Bool
    let temperature: Double?
}

struct GrokResponse: Codable {
    let id: String
    let choices: [GrokChoice]
    
    struct GrokChoice: Codable {
        let message: GrokMessage
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
}

enum GrokModelType: String, CaseIterable, Identifiable {
    case fastReasoning = "grok-4-1-fast-reasoning"
    case fastNonReasoning = "grok-4-1-fast-non-reasoning"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .fastReasoning: return "Grok 4.1 Fast Reasoning"
        case .fastNonReasoning: return "Grok 4.1 Fast"
        }
    }
}
