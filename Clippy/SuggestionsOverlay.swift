import SwiftUI
import AppKit

@MainActor
class SuggestionsOverlayViewModel: ObservableObject {
    @Published var selectedIndex: Int = 0
}

class SuggestionsWindowController: NSWindowController {
    private var onSelect: ((Item) -> Void)?
    private var onDismiss: (() -> Void)?
    private var suggestions: [Item] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackGlobalMonitor: Any?
    private var fallbackLocalMonitor: Any?
    private var viewModel = SuggestionsOverlayViewModel()
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        
        self.init(window: window)
    }
    
    deinit {
        print("🗑️ [SuggestionsWindowController] Deallocating")
        stopMonitoring()
    }
    
    func show(suggestions: [Item], searchContext: String, userPrompt: String? = nil, onSelect: @escaping (Item) -> Void, onDismiss: @escaping () -> Void) {
        print("📱 [WindowController] Showing overlay with \(suggestions.count) suggestions")
        
        // Clean up any existing monitors first
        stopMonitoring()
        
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.suggestions = suggestions
        viewModel = SuggestionsOverlayViewModel()
        
        // Ensure we have suggestions
        guard !suggestions.isEmpty else {
            print("⚠️ [WindowController] No suggestions to show!")
            onDismiss()
            return
        }
        
        let hostingController = NSHostingController(
            rootView: SuggestionsOverlay(
                suggestions: suggestions,
                searchContext: searchContext,
                userPrompt: userPrompt,
                viewModel: viewModel,
                onSelect: { [weak self] item in
                    print("✅ [WindowController] Item selected via UI")
                    self?.onSelect?(item)
                },
                onDismiss: { [weak self] in
                    print("❌ [WindowController] Dismissed via UI")
                    self?.onDismiss?()
                }
            )
        )
        
        window?.contentViewController = hostingController
        
        // Center window on screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let width: CGFloat = 560
            let rowHeight: CGFloat = 84
            let baseHeight: CGFloat = 116 // header + padding
            let height = baseHeight + rowHeight * CGFloat(min(3, suggestions.count))
            let margin: CGFloat = 24
            let x = screenRect.minX + margin
            let y = screenRect.minY + margin
            let frame = NSRect(x: x, y: y, width: width, height: height)
            window?.setFrame(frame, display: true)
        }
        
        // Force layout
        window?.layoutIfNeeded()
        
        // Show window WITHOUT stealing focus!
        window?.orderFront(nil)
        
        // DO NOT activate Clippy - keep focus on the source app!
        // This way the overlay appears but the user's text field stays focused
        
        // Start listening to keyboard events
        startMonitoring()
        
        print("✅ [WindowController] Window displayed")
    }
    
    func hide() {
        print("🚪 [WindowController] Hiding overlay")
        stopMonitoring()
        window?.orderOut(nil)
        window?.contentViewController = nil
    }
    
    private func startMonitoring() {
        if !startEventTap() {
            startFallbackMonitors()
        }
    }

    private func startEventTap() -> Bool {
        print("⌨️ [WindowController] Installing event tap")
        stopEventTap()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<SuggestionsWindowController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleCGEvent(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ [WindowController] Failed to create event tap")
            return false
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("   ✅ Event tap installed")
            return true
        }
        return false
    }
    
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        print("   📴 Event tap removed")
    }
    
    private func startFallbackMonitors() {
        print("⌨️ [WindowController] Installing fallback monitors")
        stopFallbackMonitors()
        fallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            _ = self.handleKey(code: Int64(event.keyCode))
        }
        fallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKey(code: Int64(event.keyCode)) ? nil : event
        }
        print("   ✅ Fallback monitors installed")
    }

    private func stopFallbackMonitors() {
        if let monitor = fallbackGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            fallbackGlobalMonitor = nil
        }
        if let monitor = fallbackLocalMonitor {
            NSEvent.removeMonitor(monitor)
            fallbackLocalMonitor = nil
        }
    }

    private func stopMonitoring() {
        stopEventTap()
        stopFallbackMonitors()
    }

    private func handleCGEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return handleKey(code: keyCode) ? nil : Unmanaged.passUnretained(event)
    }

    private func handleKey(code keyCode: Int64) -> Bool {
        guard !suggestions.isEmpty else { return false }
        switch keyCode {
        case 53: // esc
            DispatchQueue.main.async { [weak self] in
                self?.onDismiss?()
            }
            return true
        case 125: // down arrow
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let maxIndex = self.suggestions.count - 1
                self.viewModel.selectedIndex = min(self.viewModel.selectedIndex + 1, maxIndex)
            }
            return true
        case 126: // up arrow
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.viewModel.selectedIndex = max(self.viewModel.selectedIndex - 1, 0)
            }
            return true
        case 36, 76: // return / keypad enter
            DispatchQueue.main.async { [weak self] in
                self?.performSelection()
            }
            return true
        case 18, 19, 20, 21, 22, 23, 25, 26, 28: // digits 1-9
            let mapping: [Int64: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
            if let mapped = mapping[keyCode], mapped < suggestions.count {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.viewModel.selectedIndex = mapped
                    self.performSelection()
                }
                return true
            }
            return false
        default:
            return false
        }
    }

    private func performSelection() {
        let index = min(max(viewModel.selectedIndex, 0), suggestions.count - 1)
        let selectedItem = suggestions[index]
        onSelect?(selectedItem)
    }
}

struct SuggestionsOverlay: View {
    let suggestions: [Item]
    let searchContext: String
    let userPrompt: String?
    @ObservedObject var viewModel: SuggestionsOverlayViewModel
    let onSelect: (Item) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Paste Suggestions")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Show user prompt if available, otherwise search context
                    if let prompt = userPrompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("💬 \"\(prompt)\"")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(2)
                    } else {
                        Text("🎯 \(searchContext)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Text("↑/↓ move • Return paste • ESC cancel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            if suggestions.isEmpty {
                EmptySuggestionsView()
            } else {
                SuggestionsListView(suggestions: suggestions, viewModel: viewModel, onSelect: onSelect)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            print("🎨 [Overlay] View appeared with \(suggestions.count) suggestions")
        }
    }
}

private struct EmptySuggestionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No suggestions found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Copy something first, then press Option+X")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct SuggestionsListView: View {
    let suggestions: [Item]
    @ObservedObject var viewModel: SuggestionsOverlayViewModel
    let onSelect: (Item) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { (index, item) in
                SuggestionRow(index: index,
                              item: item,
                              isSelected: viewModel.selectedIndex == index,
                              onSelect: {
                                  onSelect(item)
                              })
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            print("📋 [Overlay] ForEach appeared with \(suggestions.count) items")
            for (i, item) in suggestions.enumerated() {
                print("   Item \(i+1): '\(item.content.prefix(30))'...")
            }
        }
    }
}

private struct SuggestionRow: View {
    let index: Int
    let item: Item
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: {
            print("🖱️ [Overlay] Button clicked for item \(index + 1)")
            onSelect()
        }) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    let displayContent = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(displayContent.isEmpty ? "[Empty content]" : displayContent)
                        .lineLimit(3)
                        .font(.system(.body, design: .default))
                        .foregroundColor(displayContent.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    metadata
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue.opacity(0.8) : Color.blue.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .frame(height: 84)
    }
    
    private var metadata: some View {
        HStack(spacing: 12) {
            if let appName = item.appName {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge")
                        .font(.caption2)
                    Text(appName)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(item.timestamp, style: .relative)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            Spacer()
            if item.content.count > 100 {
                Text("\(item.content.count) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
    }
}


