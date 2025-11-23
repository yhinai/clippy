import SwiftUI
import SwiftData

struct ClipboardDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var embeddingService: EmbeddingService
    @State private var newTagInput: String = ""
    @State private var isEditingTags: Bool = false
    
    // We need to access the embedding service to delete vectors when deleting items
    // But deleting is usually done from the list or via a closure. 
    // For this view, I'll just handle the visual editing. 
    // The delete action might need to be passed in or handled by environment object if we want to use the service.
    // I'll use the ClipboardService singleton, but it needs the embedding service instance.
    // For now, I'll focus on the UI and basic model updates.
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header / Title
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.content)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    
                    HStack {
                        if let appName = item.appName {
                            Label(appName, systemImage: "app")
                        }
                        Text("•")
                        Text(item.timestamp, format: .dateTime.day().month().hour().minute())
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Main Content Display
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONTENT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    if item.contentType == "image", let imagePath = item.imagePath, let nsImage = ClipboardService.shared.loadImage(from: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .frame(maxHeight: 500)
                            .shadow(radius: 2)
                    } else {
                        Text(item.content)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                            .textSelection(.enabled)
                    }
                }
                
                // Tags Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("TAGS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: { isEditingTags.toggle() }) {
                            Label(isEditingTags ? "Done" : "Edit", systemImage: isEditingTags ? "checkmark.circle" : "pencil.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    FlowLayout(spacing: 8) {
                        ForEach(item.tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.subheadline)
                                
                                if isEditingTags {
                                    Button(action: { removeTag(tag) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(16)
                        }
                        
                        if isEditingTags {
                            HStack {
                                TextField("New tag", text: $newTagInput)
                                    .textFieldStyle(.plain)
                                    .frame(width: 80)
                                    .onSubmit { addTag() }
                                
                                Button(action: addTag) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    item.isFavorite.toggle()
                }) {
                    Label("Favorite", systemImage: item.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(item.isFavorite ? .red : .primary)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: copyContent) {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: deleteItem) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private func copyContent() {
        if item.contentType == "image", let imagePath = item.imagePath {
            ClipboardService.shared.copyImageToClipboard(imagePath: imagePath)
        } else {
            ClipboardService.shared.copyTextToClipboard(item.content)
        }
    }
    
    private func deleteItem() {
        ClipboardService.shared.deleteItem(item, modelContext: modelContext, embeddingService: embeddingService)
    }
    
    private func addTag() {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !item.tags.contains(trimmed) else {
            newTagInput = ""
            return
        }
        
        item.tags.append(trimmed)
        newTagInput = ""
    }
    
    private func removeTag(_ tag: String) {
        item.tags.removeAll { $0 == tag }
    }
}

