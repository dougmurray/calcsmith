import CalcsmithCore
import SwiftUI

public struct FormulaDetailView: View {
    let formula: Formula
    var store: FormulaStore
    @FocusState private var focusedSymbol: String?

    public init(formula: Formula, store: FormulaStore) {
        self.formula = formula
        self.store = store
    }

    private var session: FormulaSession { store.session(formula) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if formula.variants.count > 1 { subjectPicker }
                Text(session.variant.expression)
                    .font(.system(.title2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                inputs
                resultCard
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(formula.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { prefixBar }
        }
        #endif
        .modifier(TabCyclesSubject { forward in cycle(forward: forward) })
        .onChange(of: store.focusInputsRequest) { focusFirstInput() }
        .onAppear { if store.inputFocusPending { focusFirstInput() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formula.topic.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formula.name).font(.largeTitle.weight(.semibold))
            if let note = formula.note {
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Solve for").font(.headline)
                Spacer()
                #if os(macOS)
                Text("⇥ Tab / ⇧⇥ to change subject")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            Picker("Solve for", selection: Binding(
                get: { session.variantIndex },
                set: { i in store.update(formula) { $0.selectVariant(i) } }
            )) {
                ForEach(formula.variants.indices, id: \.self) { i in
                    Text(formula.variants[i].solvesFor).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var inputs: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(Array(session.variant.inputs.enumerated()), id: \.element.symbol) { idx, input in
                GridRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(input.symbol).font(.system(.body, design: .monospaced).weight(.semibold))
                        Text(input.name).font(.caption).foregroundStyle(.secondary)
                    }
                    .gridColumnAlignment(.leading)

                    TextField(input.symbol, text: Binding(
                        get: { session.inputs[input.symbol] ?? "" },
                        set: { text in store.update(formula) { $0.inputs[input.symbol] = text } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedSymbol, equals: input.symbol)
                    .onSubmit { focusNext(after: idx) }
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                    parsedValue(input)
                        .frame(minWidth: 110, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func parsedValue(_ input: Var) -> some View {
        switch session.value(for: input) {
        case .success(let v):
            Text(EngineeringFormatter.quantity(v, unit: input.unit))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        case .failure:
            Text("invalid").font(.callout).foregroundStyle(.red)
        }
    }

    private var resultCard: some View {
        let variant = session.variant
        return VStack(alignment: .leading, spacing: 8) {
            switch session.result {
            case .success(let value):
                HStack(alignment: .firstTextBaseline) {
                    Text(variant.solvesFor + " =")
                        .font(.system(.title, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(EngineeringFormatter.quantity(value, unit: variant.unit))
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer()
                    Button {
                        Clipboard.copy(EngineeringFormatter.quantity(value, unit: variant.unit))
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy result as shown")
                }
                Text(EngineeringFormatter.scientific(value) + (variant.unit.isEmpty ? "" : " \(variant.unit)"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .failure(let error):
                Text(error.message).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    #if os(iOS)
    /// SI prefixes and units are awkward on the numeric keyboard; offer them above it.
    private var prefixBar: some View {
        HStack {
            ForEach(["M", "k", "m", "μ", "n", "p", "f", "e"], id: \.self) { p in
                Button(p) {
                    guard let sym = focusedSymbol else { return }
                    store.update(formula) { $0.inputs[sym, default: ""] += p }
                }
                .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            Spacer()
            Button("Next") { if let sym = focusedSymbol, let i = session.variant.inputs.firstIndex(where: { $0.symbol == sym }) { focusNext(after: i) } }
        }
    }
    #endif

    private func cycle(forward: Bool) {
        let keep = focusedSymbol
        store.update(formula) { $0.cycleVariant(forward: forward) }
        // The focused symbol may now be the subject (no longer an input); fall back to the first input.
        let symbols = store.session(formula).variant.inputs.map(\.symbol)
        focusedSymbol = keep.flatMap { symbols.contains($0) ? $0 : nil } ?? (keep == nil ? nil : symbols.first)
    }

    private func focusFirstInput() {
        store.inputFocusPending = false
        focusedSymbol = session.variant.inputs.first?.symbol
    }

    private func focusNext(after idx: Int) {
        let inputs = session.variant.inputs
        focusedSymbol = idx + 1 < inputs.count ? inputs[idx + 1].symbol : nil
    }
}

/// Tab / Shift-Tab change the formula's subject, like analog_engineer_assistant.
///
/// On macOS text fields consume Tab for focus traversal before SwiftUI's key handlers
/// see it, so a local event monitor intercepts it while this view is on screen.
struct TabCyclesSubject: ViewModifier {
    let cycle: (_ forward: Bool) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(TabMonitor(cycle: cycle))
        #else
        content
            .onKeyPress(.tab, phases: .down) { press in
                cycle(!press.modifiers.contains(.shift))
                return .handled
            }
        #endif
    }
}

#if os(macOS)
import AppKit

private struct TabMonitor: NSViewRepresentable {
    let cycle: (_ forward: Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.cycle = cycle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator(cycle: cycle) }

    @MainActor
    final class Coordinator {
        var cycle: (_ forward: Bool) -> Void
        private var monitor: Any?
        private weak var view: NSView?

        init(cycle: @escaping (_ forward: Bool) -> Void) { self.cycle = cycle }

        func install(on view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 48,  // Tab
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty
                else { return event }
                let windowNumber = event.windowNumber
                let shift = event.modifierFlags.contains(.shift)
                // Local monitors run on the main thread.
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.view?.window,
                          window.windowNumber == windowNumber
                    else { return false }
                    self.cycle(!shift)
                    return true
                }
                return handled ? nil : event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
