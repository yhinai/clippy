import SwiftUI
import AppKit
import ImageIO

// MARK: - 1. Main View
struct DogLoadingView: View {
    let isLoading: Bool
    let message: String
    // Used to force a restart of the "Walk In" animation if needed
    let animationResetID: UUID
    
    init(isLoading: Bool = false, message: String = "", animationResetID: UUID = UUID()) {
        self.isLoading = isLoading
        self.message = message
        self.animationResetID = animationResetID
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The Dog Animation
            AnimatedDogPlayer(isProcessing: isLoading, resetID: animationResetID)
                .frame(width: 77, height: 77)
                .background(Color.clear)
            
            // The "Thinking" Cloud (Only shows when loading)
            if isLoading {
                ThinkingCloud()
                    .frame(width: 51, height: 51)
                    .offset(x: 13, y: -10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 128, height: 128)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isLoading)
    }
}

// MARK: - 2. The Animation Engine (NSViewRepresentable)
struct AnimatedDogPlayer: NSViewRepresentable {
    let isProcessing: Bool
    let resetID: UUID
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        
        container.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        context.coordinator.imageView = imageView
        
        // Load GIF from Bundle
        if let gifURL = Bundle.main.url(forResource: "CuteDog", withExtension: "gif"),
           let gifData = try? Data(contentsOf: gifURL),
           let source = CGImageSourceCreateWithData(gifData as CFData, nil) {
            
            var frames: [NSImage] = []
            let count = CGImageSourceGetCount(source)
            for i in 0..<count {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                    frames.append(NSImage(cgImage: cgImage, size: NSSize(width: 128, height: 128)))
                }
            }
            context.coordinator.frames = frames
        }
        
        Task { await context.coordinator.startAnimation(resetID: resetID) }
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update animation speed immediately when state changes
        context.coordinator.updateState(isProcessing: isProcessing, resetID: resetID)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    // MARK: - Coordinator (The Brain)
    class Coordinator: NSObject {
        var imageView: NSImageView?
        var frames: [NSImage] = []
        var timer: Timer?
        var currentFrame = 0
        var currentResetID = UUID()
        
        // State Flags
        var isPlayingIntro = true
        var isPlayingReverse = false
        var isProcessing = false
        
        // Perfect Frame Ranges (From original code)
        let introStart = 0
        let introEnd = 299
        let loopStart = 132
        let loopEnd = 299
        
        @MainActor
        func startAnimation(resetID: UUID) {
            currentResetID = resetID
            currentFrame = introStart
            isPlayingIntro = true
            isPlayingReverse = false
            startTimer()
        }
        
        @MainActor
        func updateState(isProcessing: Bool, resetID: UUID) {
            // If ID changed, restart the "Walk In" animation
            if resetID != currentResetID {
                startAnimation(resetID: resetID)
            }
            
            // If processing state changed, update speed
            if self.isProcessing != isProcessing {
                self.isProcessing = isProcessing
                startTimer() // Restart timer with new speed
            }
        }
        
        private func startTimer() {
            timer?.invalidate()
            // 30 FPS Normal, 60 FPS when Thinking
            let interval = isProcessing ? (1.0/60.0) : (1.0/30.0)
            
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.advanceFrame()
            }
        }
        
        private func advanceFrame() {
            guard !frames.isEmpty else { return }
            imageView?.image = frames[currentFrame]
            
            // COMPLEX LOOPING LOGIC (The "Perfect" part)
            if isPlayingIntro {
                // 1. Play Walk-In (0 -> 299)
                if currentFrame >= introEnd {
                    isPlayingIntro = false
                    isPlayingReverse = true // Start breathing out
                    currentFrame = loopEnd
                } else {
                    currentFrame += 1
                }
            } else if isPlayingReverse {
                // 2. Breathe Out (299 -> 132)
                if currentFrame <= loopStart {
                    isPlayingReverse = false // Start breathing in
                    currentFrame = loopStart
                } else {
                    currentFrame -= 1
                }
            } else {
                // 3. Breathe In (132 -> 299)
                if currentFrame >= loopEnd {
                    isPlayingReverse = true // Start breathing out
                    currentFrame = loopEnd
                } else {
                    currentFrame += 1
                }
            }
        }
    }
}

// MARK: - 3. Custom Thinking Cloud
struct ThinkingCloud: View {
    @State private var scale: CGFloat = 0.8
    @State private var dotOpacity1: Double = 0.3
    @State private var dotOpacity2: Double = 0.3
    @State private var dotOpacity3: Double = 0.3
    
    var body: some View {
        ZStack {
            CloudShape()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
                .scaleEffect(scale)
            
            HStack(spacing: 4) {
                Circle().opacity(dotOpacity1)
                Circle().opacity(dotOpacity2)
                Circle().opacity(dotOpacity3)
            }
            .foregroundColor(.gray)
            .frame(height: 6)
            .offset(y: -3)
        }
        .onAppear {
            // Breathing cloud
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scale = 1.0
            }
            // Cascading dots
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { dotOpacity1 = 1.0 }
            withAnimation(.easeInOut(duration: 0.6).delay(0.2).repeatForever()) { dotOpacity2 = 1.0 }
            withAnimation(.easeInOut(duration: 0.6).delay(0.4).repeatForever()) { dotOpacity3 = 1.0 }
        }
    }
}

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        
        // Draw classic cloud bubble
        path.addEllipse(in: CGRect(x: w*0.1, y: h*0.25, width: w*0.35, height: h*0.35))
        path.addEllipse(in: CGRect(x: w*0.3, y: h*0.15, width: w*0.4, height: h*0.4))
        path.addEllipse(in: CGRect(x: w*0.5, y: h*0.25, width: w*0.35, height: h*0.35))
        path.addRoundedRect(in: CGRect(x: w*0.15, y: h*0.35, width: w*0.7, height: h*0.4), cornerSize: CGSize(width: 10, height: 10))
        
        // Little tail pointing at dog
        path.move(to: CGPoint(x: w*0.2, y: h*0.7))
        path.addLine(to: CGPoint(x: w*0.1, y: h*0.9))
        path.addLine(to: CGPoint(x: w*0.3, y: h*0.75))
        
        return path
    }
}
