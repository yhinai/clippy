import SwiftUI
import SwiftData

enum AIServiceType: String, CaseIterable {
    case gemini = "Gemini"
    case local = "Local AI"
    
    var description: String {
        switch self {
        case .gemini:
            return "Gemini 2.5 Flash (Cloud)"
        case .local:
            return "Local Qwen3-4b (On-device)"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var clipboardMonitor = ClipboardMonitor()
    @StateObject private var embeddingService = EmbeddingService()
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var visionParser = VisionScreenParser()
    @StateObject private var textCaptureService = TextCaptureService()
    @StateObject private var floatingDogController = FloatingDogWindowController()
    
    @State private var geminiService: GeminiService = GeminiService(apiKey: "")
    @State private var localAIService: LocalAIService = LocalAIService()
    
    // Voice Input State
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var elevenLabsService: ElevenLabsService?
    @State private var isRecordingVoice = false
    
    // Navigation State
    @State private var selectedCategory: NavigationCategory? = .allItems
    @State private var selectedItem: Item?
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @State private var selectedAIService: AIServiceType = .gemini
    
    // AI Processing State
    @State private var isProcessingAnswer: Bool = false
    @State private var lastCapturedText: String = ""
    @State private var thinkingStartTime: Date? // Track when thinking state started
    
    // Items Query for context (we still need this for AI context even if list has its own query)
    @Query(sort: \Item.timestamp, order: .reverse) private var allItems: [Item]

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selectedCategory,
                selectedAIService: $selectedAIService,
                floatingDogController: floatingDogController,
                showSettings: $showSettings
            )
        } content: {
            ClipboardListView(
                selectedItem: $selectedItem,
                category: selectedCategory ?? .allItems,
                searchText: searchText
            )
            .searchable(text: $searchText, placement: .sidebar)
        } detail: {
            if let item = selectedItem {
                ClipboardDetailView(item: item)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select an item to view details")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .environmentObject(embeddingService)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                apiKey: Binding(
                    get: { getStoredAPIKey() },
                    set: { saveAPIKey($0) }
                ),
                elevenLabsKey: Binding(
                    get: { UserDefaults.standard.string(forKey: "ElevenLabs_API_Key") ?? "" },
                    set: { 
                        UserDefaults.standard.set($0, forKey: "ElevenLabs_API_Key")
                        if !$0.isEmpty {
                            elevenLabsService = ElevenLabsService(apiKey: $0)
                        } else {
                            elevenLabsService = nil
                        }
                    }
                ),
                selectedService: $selectedAIService
            )
        }
        .onChange(of: selectedAIService) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "SelectedAIService")
        }
        .onChange(of: clipboardMonitor.hasAccessibilityPermission) { _, granted in
            if granted && !hotkeyManager.isListening {
                print("🔓 [ContentView] Permissions granted, restarting HotkeyManager...")
                startHotkeys()
            }
        }
        .onAppear {
            setupServices()
        }
        .onDisappear {
            clipboardMonitor.stopMonitoring()
            hotkeyManager.stopListening()
        }
    }
    
    // MARK: - Setup & Services
    
    private func setupServices() {
        // Load stored AI service selection
        if let savedServiceString = UserDefaults.standard.string(forKey: "SelectedAIService"),
           let savedService = AIServiceType(rawValue: savedServiceString) {
            selectedAIService = savedService
        }
        
        // Load stored API key
        let storedKey = getStoredAPIKey()
        if !storedKey.isEmpty {
            geminiService = GeminiService(apiKey: storedKey)
        }
        
        // Initialize ElevenLabs Service
        let elevenLabsKey = getStoredElevenLabsKey()
        if !elevenLabsKey.isEmpty {
            elevenLabsService = ElevenLabsService(apiKey: elevenLabsKey)
        }
        
        Task {
            await embeddingService.initialize()
            clipboardMonitor.startMonitoring(
                modelContext: modelContext,
                embeddingService: embeddingService,
                geminiService: geminiService
            )
            
            startHotkeys()
        }
    }
    
    private func startHotkeys() {
        hotkeyManager.startListening(
            onTrigger: { handleHotkeyTrigger() },
            onVisionTrigger: { handleVisionHotkeyTrigger() },
            onTextCaptureTrigger: { handleTextCaptureTrigger() },
            onVoiceCaptureTrigger: { toggleVoiceRecording() }
        )
    }
    
    private func toggleVoiceRecording() {
        if isRecordingVoice {
            // STOP Recording & Process
            isRecordingVoice = false
            floatingDogController.setState(.thinking) // Dog looks like it's thinking
            
            guard let url = audioRecorder.stopRecording() else { return }
            guard let service = elevenLabsService else {
                floatingDogController.updateMessage("ElevenLabs API Key missing! 🔑")
                return
            }
            
            Task {
                do {
                    // 1. Transcribe via ElevenLabs
                    let text = try await service.transcribe(audioFileURL: url)
                    
                    // 2. Feed into existing logic (same as typing)
                    if !text.isEmpty {
                        processCapturedText(text)
                    } else {
                        floatingDogController.updateMessage("I didn't catch that 👂")
                    }
                } catch {
                    print("Voice Error: \(error.localizedDescription)")
                    floatingDogController.updateMessage("Couldn't hear you 🙉")
                }
            }
        } else {
            // START Recording
            // Check if service is available before starting
            if elevenLabsService == nil {
                floatingDogController.updateMessage("Set ElevenLabs API Key in Settings ⚙️")
                return
            }
            
            isRecordingVoice = true
            _ = audioRecorder.startRecording()
            floatingDogController.setState(.idle, message: "Listening... 🎙️")
        }
    }
    
    // MARK: - Logic Handlers
    
    private func handleHotkeyTrigger() {
        print("\n🔥 [ContentView] Hotkey triggered (Option+X)")
        // Managed by TextCaptureService now
    }
    
    private func handleVisionHotkeyTrigger() {
        print("\n👁️ [ContentView] Vision hotkey triggered (Option+V)")
        visionParser.parseCurrentScreen { result in
            switch result {
            case .success(let parsedContent):
                print("✅ Vision parsing successful!")
                if !parsedContent.fullText.isEmpty {
                    saveVisionContent(parsedContent.fullText)
                }
            case .failure(let error):
                print("❌ Vision parsing failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveVisionContent(_ text: String) {
        // Deduplication check could be done here, but simplified for brevity
        let item = Item(
            timestamp: Date(),
            content: text,
            appName: clipboardMonitor.currentAppName,
            contentType: "vision-parsed"
        )
        modelContext.insert(item)
    }
    
    private func handleTextCaptureTrigger() {
        print("\n⌨️ [ContentView] Text capture hotkey triggered (Option+X)")
        
        if textCaptureService.isCapturing {
            // Second press: Stop capturing and start thinking
            floatingDogController.setState(.thinking)
            thinkingStartTime = Date() // Record when thinking started
            textCaptureService.stopCapturing()
        } else {
            // First press: Start capturing with idle state
            floatingDogController.setState(.idle)
            textCaptureService.startCapturing(
                onTypingDetected: {
                    // Switch to writing state when user starts typing
                    self.floatingDogController.setState(.writing)
                },
                onComplete: { capturedText in
                    self.lastCapturedText = capturedText
                    self.processCapturedText(capturedText)
                }
            )
        }
    }
    
    private func processCapturedText(_ capturedText: String) {
        print("\n🎯 [ContentView] Processing captured text...")
        isProcessingAnswer = true
        
        // Ensure thinking state is set and time is recorded
        if thinkingStartTime == nil {
            thinkingStartTime = Date()
        }
        floatingDogController.setState(.thinking)
        
        Task {
            // Get recent clipboard items for context
            let recentItems = Array(allItems.prefix(10))
            let clipboardContext = recentItems.map { (content: $0.content, tags: $0.tags) }
            
            let answer: String?
            let imageIndex: Int?
            
            switch selectedAIService {
            case .gemini:
                (answer, imageIndex) = await geminiService.generateAnswerWithImageDetection(
                    question: capturedText,
                    clipboardContext: clipboardContext,
                    appName: clipboardMonitor.currentAppName
                )
            case .local:
                answer = await localAIService.generateAnswer(
                    question: capturedText,
                    clipboardContext: clipboardContext,
                    appName: clipboardMonitor.currentAppName
                )
                imageIndex = nil
            }
            
            await MainActor.run {
                handleAIResponse(answer: answer, imageIndex: imageIndex, recentItems: recentItems)
            }
        }
    }
    
    private func handleAIResponse(answer: String?, imageIndex: Int?, recentItems: [Item]) {
        // Calculate how long we've been in thinking state
        let elapsed = Date().timeIntervalSince(thinkingStartTime ?? Date())
        let remainingDelay = max(0, 3.0 - elapsed) // Minimum 3 seconds of thinking
        
        print("🎯 [ContentView] AI response received. Elapsed: \(elapsed)s, Remaining delay: \(remainingDelay)s")
        
        // Delay transition to done state if needed to ensure minimum 3s thinking
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
            self.isProcessingAnswer = false
            self.thinkingStartTime = nil // Reset thinking timer
            
            // Transition to done state
            self.floatingDogController.setState(.done)
            
            if let imageIndex = imageIndex, imageIndex > 0, imageIndex <= recentItems.count {
                let item = recentItems[imageIndex - 1]
                if item.contentType == "image", let imagePath = item.imagePath {
                    ClipboardService.shared.copyImageToClipboard(imagePath: imagePath)
                    
                    // Delete original item logic
                    ClipboardService.shared.deleteItem(item, modelContext: self.modelContext, embeddingService: self.embeddingService)
                    
                    self.textCaptureService.replaceCapturedTextWithAnswer("")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.simulatePaste()
                        self.floatingDogController.updateMessage("Image pasted! 🖼️", isLoading: false)
                    }
                } else {
                    self.floatingDogController.updateMessage("That's not an image 🤔", isLoading: false)
                }
            } else if let answer = answer?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
                self.textCaptureService.replaceCapturedTextWithAnswer(answer)
                self.floatingDogController.updateMessage("Answer ready! 🎉", isLoading: false)
            } else {
                self.floatingDogController.updateMessage("Question not relevant to clipboard 📋", isLoading: false)
            }
        }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vKeyDown?.flags = .maskCommand
        vKeyUp?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
    }
    
    // MARK: - API Key Helpers
    
    private func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "Gemini_API_Key")
        geminiService = GeminiService(apiKey: key)
        // Restart monitoring
        clipboardMonitor.stopMonitoring()
        clipboardMonitor.startMonitoring(
            modelContext: modelContext,
            embeddingService: embeddingService,
            geminiService: geminiService
        )
    }
    
    private func getStoredAPIKey() -> String {
        // 1. Check process environment
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty { return envKey }
        
        // 2. Check UserDefaults
        if let stored = UserDefaults.standard.string(forKey: "Gemini_API_Key"), !stored.isEmpty {
            return stored
        }
        
        // 3. Check local .env file manually (Fallback for development)
        let envPath = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env")
        if let content = try? String(contentsOf: envPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.starts(with: "GEMINI_API_KEY=") {
                    return line.replacingOccurrences(of: "GEMINI_API_KEY=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return ""
    }
    
    private func getStoredElevenLabsKey() -> String {
        // 1. Check process environment
        if let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !envKey.isEmpty { return envKey }
        
        // 2. Check UserDefaults
        if let stored = UserDefaults.standard.string(forKey: "ElevenLabs_API_Key"), !stored.isEmpty {
            return stored
        }
        
        // 3. Check local .env file manually (Fallback for development)
        let envPath = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env")
        if let content = try? String(contentsOf: envPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if line.starts(with: "ELEVENLABS_API_KEY=") {
                    return line.replacingOccurrences(of: "ELEVENLABS_API_KEY=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        return ""
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var apiKey: String
    @Binding var elevenLabsKey: String
    @Binding var selectedService: AIServiceType
    
    @State private var tempGeminiKey: String = ""
    @State private var tempElevenLabsKey: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Gemini API Key")
                            .font(.headline)
                        
                        SecureField("Enter Gemini API key...", text: $tempGeminiKey)
                            .textFieldStyle(.roundedBorder)
                            .onAppear { tempGeminiKey = apiKey }
                        
                        Text("Required for Gemini services. Keys are stored locally.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ElevenLabs API Key")
                            .font(.headline)
                        
                        SecureField("Enter ElevenLabs API key...", text: $tempElevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                            .onAppear { tempElevenLabsKey = elevenLabsKey }
                        
                        Text("Required for voice input (Option+Space). Keys are stored locally.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    apiKey = tempGeminiKey
                    elevenLabsKey = tempElevenLabsKey
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 450, height: 350)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
