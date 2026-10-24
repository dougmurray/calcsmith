import CalcsmithCore
import SwiftUI

public enum AppMode: String, CaseIterable, Identifiable {
    case calculator = "Calculator"
    case formulas = "Formulas"
    public var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .calculator: return "plus.forwardslash.minus"
        case .formulas: return "function"
        }
    }
}

/// Top-level view shared by both apps: scientific calculator (default) plus the formula library.
public struct CalcsmithRootView: View {
    @State private var calculator = CalculatorModel()
    @State private var formulas = FormulaStore()
    @AppStorage("app.mode") private var mode: AppMode = .calculator
    @FocusState private var searchFocused: Bool

    public init() {}

    public var body: some View {
        #if os(macOS)
        Group {
            switch mode {
            case .calculator: CalculatorView(model: calculator)
            case .formulas: FormulaBrowserView(store: formulas, searchFocused: $searchFocused)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(AppMode.allCases) { m in
                        Label(m.rawValue, systemImage: m.systemImage).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch mode (⌘1 Calculator, ⌘2 Formulas)")
            }
        }
        .background { modeShortcuts }
        .onChange(of: mode) { _, new in
            // Typing goes straight to search when the formula list opens.
            if new == .formulas { focusSearchSoon() }
        }
        .onAppear { if mode == .formulas { focusSearchSoon() } }
        #else
        TabView(selection: $mode) {
            Tab(AppMode.calculator.rawValue, systemImage: AppMode.calculator.systemImage, value: .calculator) {
                CalculatorView(model: calculator)
            }
            Tab(AppMode.formulas.rawValue, systemImage: AppMode.formulas.systemImage, value: .formulas) {
                FormulaBrowserView(store: formulas, searchFocused: $searchFocused)
            }
        }
        #endif
    }

    #if os(macOS)
    /// Invisible buttons that carry the ⌘1 / ⌘2 / ⌘F shortcuts.
    private var modeShortcuts: some View {
        ZStack {
            Button("Calculator") { mode = .calculator }.keyboardShortcut("1")
            Button("Formulas") { mode = .formulas }.keyboardShortcut("2")
            Button("Find Formula") {
                mode = .formulas
                focusSearchSoon()
            }
            .keyboardShortcut("f")
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func focusSearchSoon() {
        // The search field only exists once the formulas view is installed.
        DispatchQueue.main.async { searchFocused = true }
    }
    #endif
}
