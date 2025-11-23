import SwiftUI
import AppKit

struct ClippySpriteView: View {
    let animationName: String
    let isThinking: Bool
    
    @StateObject private var engine = ClippyEngine()
    
    init(animationName: String = "Idle1_1", isThinking: Bool = false) {
        self.animationName = animationName
        self.isThinking = isThinking
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let spriteSheet = engine.spriteSheet, let currentFrame = engine.currentFrameData {
                // 1. Crop the specific frame from the map.png
                Image(nsImage: spriteSheet)
                    .resizable()
                    // The secret sauce: Cropping!
                    // We show the whole image but mask/frame it to show only the 124x93 px window
                    // Actually, easier in SwiftUI: Use .scaleEffect and .offset inside a clipped frame
                    // But map.png is massive. Better to draw it using a custom Canvas or CGImage slicing.
                    .modifier(SpriteFrameModifier(
                        sheet: spriteSheet,
                        frameX: currentFrame.x,
                        frameY: currentFrame.y,
                        frameWidth: engine.agentData?.frameWidth ?? 124,
                        frameHeight: engine.agentData?.frameHeight ?? 93
                    ))
            } else {
                ProgressView()
            }
        }
        .frame(width: 124, height: 93)
        .onAppear {
            engine.loadAssets()
            engine.playAnimation(animationName)
        }
        .onChange(of: animationName) { _, newName in
            engine.playAnimation(newName)
        }
        .onChange(of: isThinking) { _, thinking in
            if thinking {
                engine.playAnimation("Thinking") // Or "Processing"
            } else {
                engine.playAnimation("Idle1_1")
            }
        }
    }
}

// Efficiently render just one frame of the massive PNG
struct SpriteFrameModifier: ViewModifier {
    let sheet: NSImage
    let frameX: CGFloat
    let frameY: CGFloat
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    
    func body(content: Content) -> some View {
        Canvas { context, size in
            // Create a CGImage sub-image
            guard let cgImage = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            
            let cropRect = CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
            
            if let croppedCG = cgImage.cropping(to: cropRect) {
                // Draw it
                let image = Image(decorative: croppedCG, scale: 1.0)
                context.draw(image, in: CGRect(origin: .zero, size: size))
            }
        }
    }
}

// MARK: - Animation Engine

class ClippyEngine: ObservableObject {
    @Published var spriteSheet: NSImage?
    @Published var currentFrameData: ClippyFrame?
    var agentData: ClippyAgentData?
    
    private var timer: Timer?
    private var currentFrameIndex = 0
    private var currentAnimation: ClippyAnimation?
    private var currentAnimationName: String = ""
    
    // Need public init if used as @StateObject in a View struct that has an init
    init() {}
    
    func loadAssets() {
        // Parse JSON
        self.agentData = ClippyParser.loadAgentData()
        
        // Load Image
        // Check Bundle first, then dev path
        if let url = Bundle.main.url(forResource: "map", withExtension: "png", subdirectory: "Clippy"),
           let image = NSImage(contentsOf: url) {
            self.spriteSheet = image
        } else {
            // Try without subdirectory
            if let url = Bundle.main.url(forResource: "map", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                self.spriteSheet = image
            } else {
                let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("Clippy/map.png")
                if let image = NSImage(contentsOf: fileURL) {
                    self.spriteSheet = image
                } else {
                    print("❌ ClippyEngine: map.png not found")
                }
            }
        }
    }
    
    func playAnimation(_ name: String) {
        // Stop existing
        timer?.invalidate()
        
        guard let data = agentData, let animation = data.animations[name] else {
            print("⚠️ ClippyEngine: Animation '\(name)' not found")
            // Fallback to a known good animation if the requested one fails
            if name != "Idle1_1" && agentData?.animations["Idle1_1"] != nil {
                playAnimation("Idle1_1")
            }
            return
        }
        
        currentAnimationName = name
        currentAnimation = animation
        currentFrameIndex = 0
        
        // If animations are random (branching), logic goes here.
        // For now, simple playback
        
        startFrameLoop()
    }
    
    private func startFrameLoop() {
        guard let animation = currentAnimation else { return }
        
        // Get current frame
        if currentFrameIndex >= animation.frames.count {
            // Loop or stop? Clippy usually loops or goes to Idle.
            // For now, loop the current animation if it's an "Idle" one, otherwise stop
            if currentAnimationName.starts(with: "Idle") || currentAnimationName == "Thinking" || currentAnimationName == "Processing" {
                currentFrameIndex = 0
            } else {
                // Play idle after non-looping animation finishes
                playAnimation("Idle1_1")
                return
            }
        }
        
        let frame = animation.frames[currentFrameIndex]
        self.currentFrameData = frame
        
        // Schedule next frame based on duration
        let duration = Double(frame.duration) / 1000.0
        
        timer = Timer.scheduledTimer(withTimeInterval: max(duration, 0.05), repeats: false) { [weak self] _ in
            self?.currentFrameIndex += 1
            self?.startFrameLoop()
        }
    }
}

