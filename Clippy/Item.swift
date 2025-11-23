import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var content: String
    var appName: String?
    var contentType: String
    var usageCount: Int
    var vectorId: UUID?
    var tags: [String] // AI-generated semantic tags for better retrieval
    var imagePath: String? // Path to saved image file (for image clipboard items)
    var isFavorite: Bool = false
    
    init(timestamp: Date, content: String = "", appName: String? = nil, contentType: String = "text", imagePath: String? = nil, isFavorite: Bool = false) {
        self.timestamp = timestamp
        self.content = content
        self.appName = appName
        self.contentType = contentType
        self.usageCount = 0
        self.tags = []
        self.imagePath = imagePath
        self.isFavorite = isFavorite
    }
}
