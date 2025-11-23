import SwiftUI
import SwiftData

struct ClipboardListView: View {
    @Binding var selectedItem: Item?
    var category: NavigationCategory?
    var searchText: String
    
    @Query private var items: [Item]
    
    init(selectedItem: Binding<Item?>, category: NavigationCategory?, searchText: String) {
        _selectedItem = selectedItem
        self.category = category
        self.searchText = searchText
        
        let isFavorite = category == .favorites
        let search = searchText
        
        // Construct predicate based on category and search text
        // Note: Handling optionals in Predicates can be tricky. simplified for robustness.
        
        if search.isEmpty {
            if isFavorite {
                _items = Query(filter: #Predicate<Item> { item in
                    item.isFavorite
                }, sort: \.timestamp, order: .reverse)
            } else {
                _items = Query(sort: \.timestamp, order: .reverse)
            }
        } else {
            if isFavorite {
                _items = Query(filter: #Predicate<Item> { item in
                    item.isFavorite && item.content.contains(search)
                }, sort: \.timestamp, order: .reverse)
            } else {
                _items = Query(filter: #Predicate<Item> { item in
                    item.content.contains(search)
                }, sort: \.timestamp, order: .reverse)
            }
        }
    }
    
    var body: some View {
        List(selection: $selectedItem) {
            // Section by date could be done here if we fetched all and grouped
            // For now, flat list as per basic requirements, maybe section later if requested
            ForEach(items) { item in
                ClipboardItemRow(item: item)
                    .tag(item)
            }
        }
        .listStyle(.inset)
        .navigationTitle(category?.rawValue ?? "Clipboard")
    }
}

