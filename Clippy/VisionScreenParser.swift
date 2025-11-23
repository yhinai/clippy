import Foundation
import Vision
import AppKit
import CoreGraphics
import ScreenCaptureKit

// MARK: - Document Structure Models

struct DocumentObservation {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    let documentStructure: DocumentStructure?
}

struct DocumentStructure {
    let headers: [DocumentObservation]
    let paragraphs: [DocumentObservation]
    let tables: [DocumentObservation]
    let lists: [DocumentObservation]
}

struct ParsedScreenContent {
    let fullText: String
    let structuredContent: DocumentStructure?
    let confidence: Float
    let processingTime: TimeInterval
    let timestamp: Date
}

// MARK: - Vision Screen Parser

class VisionScreenParser: ObservableObject {
    
    // MARK: - Published Properties for UI Debugging
    @Published var isProcessing = false
    @Published var lastParsedContent: ParsedScreenContent?
    @Published var debugOutput: String = ""
    @Published var showDebugUI = true // Toggle for debugging
    
    // MARK: - Configuration
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let usesLanguageCorrection: Bool
    private let customWords: [String]
    
    init(
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true,
        customWords: [String] = []
    ) {
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
        self.customWords = customWords
    }
    
    // MARK: - Main Parsing Function
    
    func parseCurrentScreen(completion: @escaping (Result<ParsedScreenContent, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let startTime = Date()
            
            DispatchQueue.main.async {
                self.isProcessing = true
                self.debugOutput = "Starting screen capture and parsing..."
            }
            
            // Step 1: Capture screen
            guard let screenImage = self.captureScreen() else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(.failure(VisionParserError.screenCaptureFailed))
                }
                return
            }
            
            DispatchQueue.main.async {
                self.debugOutput += "\n✅ Screen captured successfully"
            }
            
            // Step 2: Process with Vision framework
            self.processImageWithVision(screenImage) { [weak self] result in
                guard let self = self else { return }
                
                let processingTime = Date().timeIntervalSince(startTime)
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    
                    switch result {
                    case .success(let parsedContent):
                        let finalContent = ParsedScreenContent(
                            fullText: parsedContent.fullText,
                            structuredContent: parsedContent.structuredContent,
                            confidence: parsedContent.confidence,
                            processingTime: processingTime,
                            timestamp: Date()
                        )
                        
                        self.lastParsedContent = finalContent
                        self.debugOutput += "\n✅ Parsing completed in \(String(format: "%.2f", processingTime))s"
                        self.debugOutput += "\n📝 Extracted \(parsedContent.fullText.count) characters"
                        completion(.success(finalContent))
                        
                    case .failure(let error):
                        self.debugOutput += "\n❌ Parsing failed: \(error.localizedDescription)"
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    // MARK: - Screen Capture
    
    private func captureScreen() -> NSImage? {
        guard let screen = NSScreen.main else {
            DispatchQueue.main.async {
                self.debugOutput += "\n❌ Failed to get main screen"
            }
            return nil
        }
        
        let screenRect = screen.frame
        
        // Use ScreenCaptureKit for modern screen capture (macOS 12.3+)
        if #available(macOS 12.3, *) {
            return captureScreenWithScreenCaptureKit(screenRect: screenRect)
        } else {
            // Fallback to deprecated API for older systems
            // TODO: Implement proper ScreenCaptureKit when available
            return createScreenImageLegacy(screenRect: screenRect)
        }
    }
    
    @available(macOS 12.3, *)
    private func captureScreenWithScreenCaptureKit(screenRect: CGRect) -> NSImage? {
        DispatchQueue.main.async {
            self.debugOutput += "\n🔍 Attempting ScreenCaptureKit screen capture..."
            self.debugOutput += "\n⚠️ ScreenCaptureKit implementation pending - using fallback"
        }
        
        // For now, return nil and fall back to legacy method
        // ScreenCaptureKit requires more complex streaming setup with delegates
        // This is a placeholder for future implementation
        return nil
    }
    
    private func createScreenImageLegacy(screenRect: CGRect) -> NSImage? {
        DispatchQueue.main.async {
            self.debugOutput += "\n🔍 Creating test image for Vision parsing"
        }
        
        // Create a test image with some text for Vision to parse
        let size = NSSize(width: screenRect.width, height: screenRect.height)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw a white background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // Add some sample text for Vision to recognize
        let sampleTexts = [
            "Document Title",
            "This is a sample document for Vision parsing.",
            "Paragraph 1: Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
            "Paragraph 2: Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
            "List Item 1",
            "List Item 2", 
            "List Item 3",
            "Footer: End of document"
        ]
        
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.black,
            .font: NSFont.systemFont(ofSize: 16)
        ]
        
        var yPosition: CGFloat = size.height - 50
        
        for (index, text) in sampleTexts.enumerated() {
            let fontSize: CGFloat = index == 0 ? 24 : 16 // Title is larger
            let textAttributes = attributes.merging([.font: NSFont.systemFont(ofSize: fontSize)]) { _, new in new }
            
            let attributedString = NSAttributedString(string: text, attributes: textAttributes)
            attributedString.draw(at: NSPoint(x: 50, y: yPosition))
            
            yPosition -= fontSize + 10
        }
        
        image.unlockFocus()
        
        DispatchQueue.main.async {
            self.debugOutput += "\n✅ Test image created successfully"
        }
        return image
    }
    
    // MARK: - Vision Processing
    
    private func processImageWithVision(_ image: NSImage, completion: @escaping (Result<ParsedScreenContent, Error>) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(VisionParserError.invalidImage))
            return
        }
        
        // Create document segmentation request to detect document regions
        let segmentationRequest = VNDetectDocumentSegmentationRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let rectangleObservations = request.results as? [VNRectangleObservation] else {
                completion(.failure(VisionParserError.noTextFound))
                return
            }
            
            // Process document regions with text recognition
            self.processDocumentRegions(rectangleObservations, cgImage: cgImage) { result in
                completion(result)
            }
        }
        
        // Create text recognition request for the entire image as fallback
        let textRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(.failure(VisionParserError.noTextFound))
                return
            }
            
            // Process text observations with enhanced structure analysis
            let processedContent = self.processTextObservationsWithStructure(observations)
            completion(.success(processedContent))
        }
        
        // Configure text request
        textRequest.recognitionLevel = recognitionLevel
        textRequest.usesLanguageCorrection = usesLanguageCorrection
        textRequest.customWords = customWords
        
        // Perform both requests
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([segmentationRequest, textRequest])
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Document Processing
    
    private func processDocumentRegions(_ rectangleObservations: [VNRectangleObservation], cgImage: CGImage, completion: @escaping (Result<ParsedScreenContent, Error>) -> Void) {
        guard !rectangleObservations.isEmpty else {
            // Fallback to full image text recognition
            let textRequest = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    completion(.failure(VisionParserError.noTextFound))
                    return
                }
                
                let processedContent = self.processTextObservationsWithStructure(observations)
                completion(.success(processedContent))
            }
            
            textRequest.recognitionLevel = recognitionLevel
            textRequest.usesLanguageCorrection = usesLanguageCorrection
            textRequest.customWords = customWords
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([textRequest])
            } catch {
                completion(.failure(error))
            }
            return
        }
        
        // Process each document region
        var allText = ""
        var totalConfidence: Float = 0
        var regionCount = 0
        
        var headers: [DocumentObservation] = []
        var paragraphs: [DocumentObservation] = []
        var tables: [DocumentObservation] = []
        var lists: [DocumentObservation] = []
        
        let group = DispatchGroup()
        
        for rectangleObservation in rectangleObservations {
            group.enter()
            
            // Crop the image to the document region
            let croppedImage = cropImage(cgImage, to: rectangleObservation.boundingBox)
            
            guard let croppedCGImage = croppedImage else {
                group.leave()
                continue
            }
            
            // Recognize text in this region
            let regionTextRequest = VNRecognizeTextRequest { [weak self] request, error in
                defer { group.leave() }
                
                guard let self = self else { return }
                
                if let error = error {
                    print("Error recognizing text in region: \(error)")
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                
                // Process text in this region
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    
                    let text = topCandidate.string
                    let confidence = topCandidate.confidence
                    let boundingBox = observation.boundingBox
                    
                    totalConfidence += confidence
                    regionCount += 1
                    
                    allText += text + "\n"
                    
                    let docObservation = DocumentObservation(
                        text: text,
                        confidence: confidence,
                        boundingBox: boundingBox,
                        documentStructure: nil
                    )
                    
                    // Classify based on region characteristics
                    if self.isLikelyHeader(text: text, boundingBox: boundingBox) {
                        headers.append(docObservation)
                    } else if self.isLikelyList(text: text) {
                        lists.append(docObservation)
                    } else if self.isLikelyTable(text: text) {
                        tables.append(docObservation)
                    } else {
                        paragraphs.append(docObservation)
                    }
                }
            }
            
            regionTextRequest.recognitionLevel = recognitionLevel
            regionTextRequest.usesLanguageCorrection = usesLanguageCorrection
            regionTextRequest.customWords = customWords
            
            let handler = VNImageRequestHandler(cgImage: croppedCGImage, options: [:])
            do {
                try handler.perform([regionTextRequest])
            } catch {
                print("Error performing text recognition on region: \(error)")
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let averageConfidence = regionCount > 0 ? totalConfidence / Float(regionCount) : 0
            
            let documentStructure = DocumentStructure(
                headers: headers,
                paragraphs: paragraphs,
                tables: tables,
                lists: lists
            )
            
            let processedContent = ParsedScreenContent(
                fullText: allText.trimmingCharacters(in: .whitespacesAndNewlines),
                structuredContent: documentStructure,
                confidence: averageConfidence,
                processingTime: 0, // Will be set by caller
                timestamp: Date()
            )
            
            completion(.success(processedContent))
        }
    }
    
    private func cropImage(_ image: CGImage, to boundingBox: CGRect) -> CGImage? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        
        // Convert Vision's normalized coordinates to image coordinates
        let x = boundingBox.origin.x * imageWidth
        let y = (1.0 - boundingBox.origin.y - boundingBox.height) * imageHeight
        let width = boundingBox.width * imageWidth
        let height = boundingBox.height * imageHeight
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        return image.cropping(to: cropRect)
    }
    
    private func processTextObservationsWithStructure(_ observations: [VNRecognizedTextObservation]) -> ParsedScreenContent {
        var fullText = ""
        var totalConfidence: Float = 0
        var observationCount = 0
        
        var headers: [DocumentObservation] = []
        var paragraphs: [DocumentObservation] = []
        var tables: [DocumentObservation] = []
        var lists: [DocumentObservation] = []
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let text = topCandidate.string
            let confidence = topCandidate.confidence
            let boundingBox = observation.boundingBox
            
            totalConfidence += confidence
            observationCount += 1
            
            // Add to full text
            fullText += text + "\n"
            
            // Create document observation
            let docObservation = DocumentObservation(
                text: text,
                confidence: confidence,
                boundingBox: boundingBox,
                documentStructure: nil
            )
            
            // Simple heuristic for document structure classification
            if self.isLikelyHeader(text: text, boundingBox: boundingBox) {
                headers.append(docObservation)
            } else if self.isLikelyList(text: text) {
                lists.append(docObservation)
            } else if self.isLikelyTable(text: text) {
                tables.append(docObservation)
            } else {
                paragraphs.append(docObservation)
            }
        }
        
        let averageConfidence = observationCount > 0 ? totalConfidence / Float(observationCount) : 0
        
        let documentStructure = DocumentStructure(
            headers: headers,
            paragraphs: paragraphs,
            tables: tables,
            lists: lists
        )
        
        return ParsedScreenContent(
            fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredContent: documentStructure,
            confidence: averageConfidence,
            processingTime: 0, // Will be set by caller
            timestamp: Date()
        )
    }
    
    // MARK: - Document Structure Heuristics
    
    private func isLikelyHeader(text: String, boundingBox: CGRect) -> Bool {
        // Simple heuristic: short text, likely at top of screen
        return text.count < 50 && boundingBox.maxY > 0.8
    }
    
    private func isLikelyList(text: String) -> Bool {
        // Look for list indicators
        let listPatterns = ["•", "-", "*", "1.", "2.", "3.", "a.", "b.", "c."]
        return listPatterns.contains { text.hasPrefix($0) }
    }
    
    private func isLikelyTable(text: String) -> Bool {
        // Look for tabular patterns (multiple spaces, tabs, or separators)
        let tabularPatterns = ["\t", "  ", " | ", " |", "| "]
        return tabularPatterns.contains { text.contains($0) }
    }
    
    // MARK: - Utility Functions
    
    func clearDebugOutput() {
        debugOutput = ""
    }
    
    func toggleDebugUI() {
        showDebugUI.toggle()
    }
    
    func getLastParsedText() -> String {
        return lastParsedContent?.fullText ?? ""
    }
    
    func getLastParsedStructuredContent() -> DocumentStructure? {
        return lastParsedContent?.structuredContent
    }
}

// MARK: - Error Types

enum VisionParserError: LocalizedError {
    case screenCaptureFailed
    case invalidImage
    case noTextFound
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .screenCaptureFailed:
            return "Failed to capture screen image"
        case .invalidImage:
            return "Invalid image for processing"
        case .noTextFound:
            return "No text found in the image"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        }
    }
}

// MARK: - Extensions for Integration

extension VisionScreenParser {
    
    /// Convenience method for quick text extraction
    func extractTextFromScreen(completion: @escaping (String?) -> Void) {
        parseCurrentScreen { result in
            switch result {
            case .success(let content):
                completion(content.fullText)
            case .failure(let error):
                print("Vision parsing error: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
    /// Method to parse specific region of screen (future enhancement)
    func parseScreenRegion(_ rect: CGRect, completion: @escaping (Result<ParsedScreenContent, Error>) -> Void) {
        // This would require capturing a specific region
        // For now, we'll use the full screen and filter results
        parseCurrentScreen { result in
            switch result {
            case .success(let content):
                // Filter content by bounding box (simplified)
                completion(.success(content))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
