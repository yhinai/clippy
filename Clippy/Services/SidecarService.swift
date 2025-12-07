import AppKit
import Foundation

@MainActor
class SidecarService: AIServiceProtocol, ObservableObject {
    @Published var isProcessing: Bool = false
    
    private let baseURL = "http://127.0.0.1:8000"
    
    // MARK: - AIServiceProtocol
    
    func generateAnswer(
        question: String,
        clipboardContext: [RAGContextItem],
        appName: String?
    ) async -> String? {
        isProcessing = true
        defer { isProcessing = false }
        
        // Convert RAG items to simple dictionaries for JSON
        let contextItems = clipboardContext.map { item in
            return [
                "content": item.content,
                "type": item.type,
                "timestamp": item.timestamp.description,
                "tags": item.tags
            ]
        }
        
        // Get Grok API Key from UserDefaults
        let grokKey = UserDefaults.standard.string(forKey: "Grok_API_Key") ?? ""
        
        let payload: [String: Any] = [
            "message": question,
            "context": [
                "clipboard_items": contextItems,
                "app_name": appName ?? "Unknown",
                "api_key": grokKey
            ]
        ]
        
        do {
            let response: SidecarResponse = try await sendRequest(endpoint: "/v1/agent/message", body: payload)
            
            // Handle Client-Side Tools
            if let tools = response.tool_calls {
                for tool in tools {
                    if tool.name == "paste_to_app", let content = tool.parameters["content"] {
                         print("📋 [SidecarService] Executing paste_to_app: \(content.count) chars")
                         await MainActor.run {
                             self.pasteText(content)
                         }
                    }
                }
            }
            
            return response.response
        } catch {
            print("❌ [SidecarService] Error: \(error)")
            return "Error: Could not connect to Clippy Sidecar (Python). Is it running?"
        }
    }
    
    private func pasteText(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vKeyDown?.flags = .maskCommand
        vKeyUp?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
    }
    
    func generateTags(content: String, appName: String?, context: String?) async -> [String] {
        // For now, return empty or implement a specific tag endpoint
        // TODO: Implement /v1/agent/tags in Sidecar
        return []
    }
    
    func analyzeImage(imageData: Data) async -> String? {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let response: SidecarResponse = try await uploadImage(endpoint: "/v1/agent/vision", imageData: imageData)
            return response.response
        } catch {
            print("❌ [SidecarService] Vision Error: \(error)")
            return "Error: Vision analysis failed."
        }
    }
    
    // MARK: - Memory Management
    
    func saveMemoryItem(text: String, appName: String, tags: [String] = []) async {
        let payload: [String: Any] = [
            "text": text,
            "source_app": appName,
            "tags": tags
        ]
        
        do {
            let _: [String: String] = try await sendRequest(endpoint: "/v1/memory/add", body: payload)
            print("✅ [SidecarService] Memory item saved to LanceDB")
        } catch {
            print("❌ [SidecarService] Failed to save memory item: \(error)")
        }
    }
    
    // MARK: - Network Helper
    
    struct ToolCall: Codable {
        let name: String
        let parameters: [String: String] // Simplified
    }

    private struct SidecarResponse: Codable {
        let response: String
        let tool_calls: [ToolCall]? 
    }
    
    private func uploadImage<T: Decodable>(endpoint: String, imageData: Data) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"screen_capture.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("❌ [SidecarService] Upload error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func sendRequest<T: Decodable>(endpoint: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, 
              (200...299).contains(httpResponse.statusCode) else {
            print("❌ [SidecarService] Server error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}
