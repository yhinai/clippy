import SwiftUI

enum NavigationCategory: String, CaseIterable, Identifiable {
    case allItems = "All Items"
    case favorites = "Favorites"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .allItems: return "clock.arrow.circlepath"
        case .favorites: return "heart.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: NavigationCategory?
    @Binding var selectedAIService: AIServiceType
    @ObservedObject var floatingDogController: FloatingDogWindowController
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(NavigationCategory.allCases) { category in
                        NavigationLink(value: category) {
                            Label(category.rawValue, systemImage: category.iconName)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            
            Divider()
            
            VStack(spacing: 16) {
                // AI Service Selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI SERVICE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Configure API Keys")
                    }
                    
                    Picker("AI Service", selection: $selectedAIService) {
                        ForEach(AIServiceType.allCases, id: \.self) { service in
                            Text(service.rawValue).tag(service)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                
                // Assistant Toggle
                HStack {
                    Label("Assistant", systemImage: "pawprint.fill")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $floatingDogController.followTextInput)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
    }
}

