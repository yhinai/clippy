import SwiftUI
import SwiftData

struct ClipboardListView: View {
    @Binding var selectedItems: Set<PersistentIdentifier>
    var category: NavigationCategory?
    var searchText: String
    
    @EnvironmentObject var container: AppDependencyContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.timestamp, order: .reverse) private var allItems: [Item]
    
    @State private var searchResults: [Item] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var lastClickedItemId: PersistentIdentifier? // For shift-click range selection
    
    var body: some View {
        List(selection: $selectedItems) {
            if searchText.isEmpty {
                // Normal List View
                ForEach(filteredItems) { item in
                    ClipboardItemRow(item: item, isSelected: selectedItems.contains(item.persistentModelID))
                        .tag(item)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button {
                                copyToClipboard(item)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            
                            Divider()
                            
                            Button {
                                performTransform(item, instruction: "Fix grammar and spelling.")
                            } label: {
                                Label("Fix Grammar", systemImage: "text.badge.checkmark")
                            }
                            
                            Button {
                                performTransform(item, instruction: "Summarize this text in one sentence.")
                            } label: {
                                Label("Summarize", systemImage: "text.quote")
                            }
                            
                            Button {
                                performTransform(item, instruction: "Convert this to valid JSON.")
                            } label: {
                                Label("To JSON", systemImage: "curlybraces")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } else {
                // Search Results View
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView("Searching...")
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {

                    ForEach(searchResults) { item in
                        ClipboardItemRow(item: item, isSelected: selectedItems.contains(item.persistentModelID))
                            .tag(item)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .tag(item)
                            .contextMenu {
                                Button {
                                    copyToClipboard(item)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                
                                Divider()
                                
                                Button {
                                    performTransform(item, instruction: "Fix grammar and spelling.")
                                } label: {
                                    Label("Fix Grammar", systemImage: "text.badge.checkmark")
                                }
                                
                                Button {
                                    performTransform(item, instruction: "Summarize this text in one sentence.")
                                } label: {
                                    Label("Summarize", systemImage: "text.quote")
                                }
                                
                                Button {
                                    performTransform(item, instruction: "Convert this to valid JSON.")
                                } label: {
                                    Label("To JSON", systemImage: "curlybraces")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    deleteItem(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listStyle(.plain)
        .navigationTitle(category?.rawValue ?? "Clipboard")
        .onChange(of: searchText) { _, newValue in
            // Cancel previous task
            searchTask?.cancel()
            
            guard !newValue.isEmpty else {
                searchResults = []
                isSearching = false
                return
            }
            
            isSearching = true
            
            searchTask = Task {
                // Debounce
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                if Task.isCancelled { return }
                
                // 1. Perform semantic search
                let results = await container.clippy.search(query: newValue, limit: 20)
                
                if Task.isCancelled { return }
                
                // 2. Map IDs back to Items
                let ids = results.map { $0.0 }
                
                await MainActor.run {
                    if Task.isCancelled { return }
                    
                    // Efficiently find items in current loaded list
                    // Note: For very large datasets, we might need a direct fetch by ID
                    let foundItems = allItems.filter { ids.contains($0.vectorId ?? UUID()) }
                    
                    // Sort by the order returned from search (relevance)
                    self.searchResults = ids.compactMap { id in
                        foundItems.first(where: { $0.vectorId == id })
                    }
                    
                    self.isSearching = false
                }
            }
        }
        .focusable()
        .onKeyPress(.escape) {
            if !selectedItems.isEmpty {
                // Delete all selected items
                for itemId in selectedItems {
                    if let item = allItems.first(where: { $0.id == itemId }) {
                        deleteItem(item)
                    }
                }
                selectedItems.removeAll()
                return .handled
            }
            return .ignored
        }
    }
    
    // Filter items based on category (when not searching)
    private var filteredItems: [Item] {
        if let category = category, category == .favorites {
            return allItems.filter { $0.isFavorite }
        }
        return allItems
    }
    
    // MARK: - Helper Methods
    
    private func performTransform(_ item: Item, instruction: String) {
        Task {
            guard let result = await container.localAIService.transformText(text: item.content, instruction: instruction) else { return }
            await MainActor.run {
                ClipboardService.shared.copyTextToClipboard(result)
            }
        }
    }
    
    private func copyToClipboard(_ item: Item) {
        ClipboardService.shared.copyTextToClipboard(item.content)
    }
    
    private func deleteItem(_ item: Item) {
        modelContext.delete(item)
        // Note: For complete consistency, we should also delete from Vector DB using ClipboardRepository if available,
        // but modelContext deletion is propagated via NotificationCenter if setup, or we rely on next app launch sync.
        // For now, this suffices for UI.
        Task {
             try? await container.clippy.deleteDocument(vectorId: item.vectorId ?? UUID())
        }
    }
}


// MARK: - Clipboard Item Row

// MARK: - Clipboard Item Row

struct ClipboardItemRow: View {
    let item: Item
    let isSelected: Bool
    @State private var actions: [ClipboardAction] = []
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Gradient Icon
            ZStack {
                Circle()
                    .fill(iconGradient)
                    .frame(width: 38, height: 38)
                    .shadow(color: iconColor.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(item.title ?? item.content)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Metadata
                HStack(spacing: 6) {
                    Text(timeAgo(from: item.timestamp))
                    
                    if let appName = item.appName {
                        Text("·")
                        Text(appName)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                
                // Tags (minimal)
                if !item.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Material.ultraThin)
                                .clipShape(Capsule())
                        }
                        if item.tags.count > 2 {
                            Text("+\(item.tags.count - 2)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(4)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear {
            if actions.isEmpty && item.contentType == "text" {
                DispatchQueue.global(qos: .background).async {
                    let detected = ActionDetector.shared.detectActions(in: item.content)
                    DispatchQueue.main.async { actions = detected }
                }
            }
        }
    }
    
    private var iconName: String {
        switch item.contentType {
        case "image": return "photo"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }
    
    private var iconColor: Color {
        switch item.contentType {
        case "image": return .blue
        case "code": return .purple
        default: return .orange
        }
    }
    
    private var iconGradient: LinearGradient {
        switch item.contentType {
        case "image":
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "code":
            return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

