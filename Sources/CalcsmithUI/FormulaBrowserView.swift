import CalcsmithCore
import SwiftUI

/// Searchable list of formulas; selecting one opens it for entering variables.
public struct FormulaBrowserView: View {
    @Bindable var store: FormulaStore
    @FocusState.Binding var searchFocused: Bool

    public init(store: FormulaStore, searchFocused: FocusState<Bool>.Binding) {
        self.store = store
        self._searchFocused = searchFocused
    }

    public var body: some View {
        #if os(macOS)
        // Detail on the left and the list on the right, with the divider where the calculator's
        // keypad | history divider sits; NavigationSplitView can only put its sidebar on the left.
        HStack(spacing: 0) {
            Group {
                if let id = store.selectedID, let formula = FormulaLibrary.formula(id: id) {
                    FormulaDetailView(formula: formula, store: store)
                        .id(id)
                } else {
                    ContentUnavailableView(
                        "Choose a formula", systemImage: "function",
                        description: Text("Search by name, topic, or variable. Press Return to open the top match."))
                }
            }
            .frame(width: 440)
            .frame(maxHeight: .infinity)
            Divider()
            VStack(spacing: 0) {
                searchField
                list
            }
            .frame(minWidth: 220)
        }
        #else
        NavigationStack(path: $store.path) {
            list
                .navigationTitle("Formulas")
                .navigationDestination(for: Formula.ID.self) { id in
                    if let formula = FormulaLibrary.formula(id: id) {
                        FormulaDetailView(formula: formula, store: store)
                    }
                }
        }
        #endif
    }

    private var list: some View {
        // Only macOS binds the selection: on iOS a selection binding makes rows
        // record a selection on tap instead of following their NavigationLink.
        #if os(macOS)
        List(selection: $store.selectedID) { listContent }
            .listStyle(.sidebar)
            .overlay { noResults }
        #else
        List { listContent }
            .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search formulas")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { store.openTopResult() }
            .overlay { noResults }
        #endif
    }

    @ViewBuilder
    private var listContent: some View {
        if store.isSearching {
            ForEach(store.results) { formula in
                row(formula, showTopic: true)
            }
        } else {
            ForEach(store.groupedResults, id: \.topic) { group in
                Section(group.topic) {
                    ForEach(group.formulas) { row($0, showTopic: false) }
                }
            }
        }
    }

    @ViewBuilder
    private var noResults: some View {
        if store.results.isEmpty {
            ContentUnavailableView.search(text: store.query)
        }
    }

    #if os(macOS)
    /// A plain field rather than `.searchable`: the sidebar search field swallows Return,
    /// and this one also lets ↑/↓ walk the results without leaving the keyboard.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search formulas", text: $store.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { store.openSelectedOrTopResult() }
                .onKeyPress(.downArrow) { store.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { store.moveSelection(by: -1); return .handled }
                .onExitCommand { store.query = "" }
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onChange(of: store.query) {
            // Keep the top hit selected while typing so the detail follows the search.
            if store.isSearching { store.selectedID = store.results.first?.id }
        }
    }
    #endif

    @ViewBuilder
    private func row(_ formula: Formula, showTopic: Bool) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(formula.name)
            Text(showTopic ? "\(formula.topic) · \(subjects(formula))" : subjects(formula))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        #if os(macOS)
        label.tag(formula.id)
        #else
        NavigationLink(value: formula.id) { label }
        #endif
    }

    private func subjects(_ formula: Formula) -> String {
        formula.variants.map(\.solvesFor).joined(separator: ", ")
    }
}
