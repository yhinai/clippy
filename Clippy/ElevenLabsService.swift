import Foundation

class ElevenLabsService: ObservableObject {
    private let apiKey: String
    private let scribeURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func transcribe(audioFileURL: URL) async throws -> String {
        print("📤 [ElevenLabs] Sending audio for transcription...")
        
        var request = URLRequest(url: scribeURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let data = try createMultipartBody(fileURL: audioFileURL, boundary: boundary)
        
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabs", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            print("❌ [ElevenLabs] API Error (\(httpResponse.statusCode)): \(errorMsg)")
            throw NSError(domain: "ElevenLabs", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])
        }
        
        // Parse response: {"text": "what is my gemini api key"}
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let text = json["text"] as? String {
            print("✅ [ElevenLabs] Transcription: \(text)")
            return text
        }
        
        return ""
    }
    
    private func createMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        var data = Data()
        let fileData = try Data(contentsOf: fileURL)
        
        // Add Model ID param
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n".data(using: .utf8)!)
        data.append("scribe_v1\r\n".data(using: .utf8)!)
        
        // Add File
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

