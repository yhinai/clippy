import Foundation
import SwiftUI

// MARK: - Data Models for parsing agent.js

struct ClippyAgentData: Decodable {
    let overlayCount: Int
    let sounds: [String]
    let framesize: [Int] // [width, height]
    let animations: [String: ClippyAnimation]
    
    // Helper to get dimensions
    var frameWidth: CGFloat { CGFloat(framesize[0]) }
    var frameHeight: CGFloat { CGFloat(framesize[1]) }
}

struct ClippyAnimation: Decodable {
    let frames: [ClippyFrame]
}

struct ClippyFrame: Decodable {
    let duration: Int
    let images: [[Int]]? // [[x, y]]
    let sound: String?
    let exitBranch: Int?
    let branching: ClippyBranching?
    
    // Helper to get x, y
    var x: CGFloat { CGFloat(images?.first?[0] ?? 0) }
    var y: CGFloat { CGFloat(images?.first?[1] ?? 0) }
}

struct ClippyBranching: Decodable {
    let branches: [ClippyBranch]
}

struct ClippyBranch: Decodable {
    let frameIndex: Int
    let weight: Int
}

// MARK: - JSON Parser

class ClippyParser {
    static func loadAgentData() -> ClippyAgentData? {
        guard let url = Bundle.main.url(forResource: "agent", withExtension: "js", subdirectory: "Clippy") else {
            // Fallback: Try reading from file system directly if not in bundle yet (dev mode)
            let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Clippy/agent.js")
            if let data = try? Data(contentsOf: fileURL) {
                return parseJS(data: data)
            }
            print("❌ ClippyParser: agent.js not found in Bundle or path \(fileURL.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return parseJS(data: data)
        } catch {
            print("❌ ClippyParser: Error loading agent.js: \(error)")
            return nil
        }
    }
    
    private static func parseJS(data: Data) -> ClippyAgentData? {
        // agent.js is technically JS code: clippy.ready('Clippy', { ... });
        // We need to strip the wrapper to get the JSON
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        
        // Find the start of the JSON object
        guard let startRange = string.range(of: "{"),
              let endRange = string.range(of: "});", options: .backwards) else {
            print("❌ ClippyParser: Invalid agent.js format")
            return nil
        }
        
        let jsonString = String(string[startRange.lowerBound..<endRange.lowerBound])
        
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let agentData = try JSONDecoder().decode(ClippyAgentData.self, from: jsonData)
            return agentData
        } catch {
            print("❌ ClippyParser: JSON Decode Error: \(error)")
            return nil
        }
    }
}

