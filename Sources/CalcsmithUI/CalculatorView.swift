import CalcsmithCore
import SwiftUI

public struct CalculatorView: View {
    @Bindable var model: CalculatorModel
    @FocusState private var fieldFocused: Bool

    public init(model: CalculatorModel) {
        self.model = model
    }

    public var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                display
                Keypad(model: model) { fieldFocused = true }
            }
            .padding(16)
            .frame(width: 440)
            Divider()
            HistoryList(model: model) { fieldFocused = true }
                .frame(minWidth: 220)
        }
        .onAppear { fieldFocused = true }
        #else
        VStack(spacing: 8) {
            HistoryList(model: model) {}
            display
            Keypad(model: model) {}
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        #endif
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Picker("Angle", selection: $model.angleMode) {
                    ForEach(AngleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if let last = model.lastExpression, !model.isPreview {
                    Text(last)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            expressionField

            HStack(alignment: .firstTextBaseline) {
                if let error = model.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Spacer()
                if let value = model.displayValue {
                    Text(model.format(value))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.isPreview ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .textSelection(.enabled)
                } else {
                    Text("0")
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            if let value = model.displayValue {
                Text(EngineeringFormatter.scientific(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var expressionField: some View {
        #if os(macOS)
        // Focused at launch so typing goes straight into the expression.
        TextField("Type an expression", text: $model.expression)
            .textFieldStyle(.plain)
            .font(.system(size: 20, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .focused($fieldFocused)
            .onSubmit { model.evaluate(); fieldFocused = true }
            .onChange(of: model.expression) { old, _ in model.textDidChange(from: old) }
            .onExitCommand { model.clear() }
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            Text(model.expression.isEmpty ? " " : model.expression)
                .font(.system(size: 22, design: .monospaced))
                .lineLimit(1)
        }
        .defaultScrollAnchor(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        #endif
    }
}

// MARK: - History

struct HistoryList: View {
    var model: CalculatorModel
    var refocus: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                #if os(macOS)
                if !model.history.isEmpty {
                    HStack {
                        Text("History").font(.headline)
                        Spacer()
                        Button("Clear") { model.clearHistory(); refocus() }
                            .buttonStyle(.borderless)
                    }
                }
                #endif
                ForEach(model.history) { entry in
                    Button {
                        model.insertValue(entry.value)
                        refocus()
                    } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.expression)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("= " + model.format(entry.value))
                                .font(.system(.title3, design: .rounded))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(entry.id)
                    .contextMenu {
                        Button("Insert Result") { model.insertValue(entry.value); refocus() }
                        Button("Edit Expression") { model.recall(entry); refocus() }
                        Button("Copy Result") { Clipboard.copy(EngineeringFormatter.scientific(entry.value, significantDigits: 15)) }
                        Button("Copy Engineering") { Clipboard.copy(model.format(entry.value)) }
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: model.history.count) {
                if let last = model.history.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                if let last = model.history.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

// MARK: - Keypad

struct Keypad: View {
    var model: CalculatorModel
    /// Called after every press so the Mac text field keeps keyboard focus.
    var afterPress: () -> Void

    enum Role { case digit, op, function, prefix, action, equals }

    struct Key: Identifiable {
        let label: String
        var role: Role = .function
        var action: Action
        var id: String { label }

        enum Action {
            case insert(String, separate: Bool = false)
            case clear, backspace, evaluate, ans
        }
    }

    private static func ins(_ label: String, _ text: String? = nil, _ role: Role = .function, separate: Bool = false) -> Key {
        Key(label: label, role: role, action: .insert(text ?? label, separate: separate))
    }

    private static func fn(_ label: String, _ name: String? = nil) -> Key {
        ins(label, (name ?? label) + "(", .function, separate: true)
    }

    static let scientificRows: [[Key]] = [
        [fn("sin"), fn("cos"), fn("tan"), fn("ln"), fn("log")],
        [fn("sin⁻¹", "asin"), fn("cos⁻¹", "acos"), fn("tan⁻¹", "atan"), ins("eˣ", "exp(", separate: true), ins("10ˣ", "10^", separate: true)],
        [ins("x²", "^2"), ins("xʸ", "^"), fn("√", "sqrt"), ins("1/x", "^-1"), ins("x!", "!")],
        [ins("("), ins(")"), ins("π", "π", separate: true), ins("e", "e", separate: true), ins("∥", "∥")],
    ]

    static let prefixRow: [Key] = ["p", "n", "μ", "m", "k", "M", "G"].map { ins($0, $0, .prefix) }

    static let mainRows: [[Key]] = [
        [ins("7", nil, .digit), ins("8", nil, .digit), ins("9", nil, .digit), ins("÷", "/", .op),
         Key(label: "AC", role: .action, action: .clear)],
        [ins("4", nil, .digit), ins("5", nil, .digit), ins("6", nil, .digit), ins("×", "*", .op),
         Key(label: "⌫", role: .action, action: .backspace)],
        [ins("1", nil, .digit), ins("2", nil, .digit), ins("3", nil, .digit), ins("−", "-", .op),
         ins("EE", "E", .op)],
        [ins("0", nil, .digit), ins(".", nil, .digit), Key(label: "Ans", role: .function, action: .ans),
         ins("+", "+", .op), Key(label: "=", role: .equals, action: .evaluate)],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.scientificRows.indices, id: \.self) { r in
                row(Self.scientificRows[r], height: 34)
            }
            row(Self.prefixRow, height: 30)
            ForEach(Self.mainRows.indices, id: \.self) { r in
                row(Self.mainRows[r], height: 48)
            }
        }
    }

    private func row(_ keys: [Key], height: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(keys) { key in
                Button { press(key) } label: {
                    Text(key.label)
                        .font(font(for: key.role))
                        .frame(maxWidth: .infinity, minHeight: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KeyStyle(role: key.role))
                .focusable(false)
                .modifier(KeyShortcut(key: key))
            }
        }
    }

    private func font(for role: Role) -> Font {
        switch role {
        case .digit, .op, .equals: return .system(size: 22, weight: .medium, design: .rounded)
        case .prefix: return .system(size: 15, weight: .semibold, design: .monospaced)
        case .action: return .system(size: 18, weight: .medium, design: .rounded)
        case .function: return .system(size: 15, weight: .regular, design: .rounded)
        }
    }

    private func press(_ key: Key) {
        switch key.action {
        case .insert(let text, let separate): model.insert(text, separateFromNumber: separate)
        case .clear: model.clear()
        case .backspace: model.backspace()
        case .evaluate: model.evaluate()
        case .ans: model.insert("ans", separateFromNumber: true)
        }
        afterPress()
    }
}

/// On iOS a hardware keyboard can drive the keypad; on macOS the text field takes typing directly.
private struct KeyShortcut: ViewModifier {
    let key: Keypad.Key
    func body(content: Content) -> some View {
        #if os(iOS)
        switch key.action {
        case .evaluate: content.keyboardShortcut(.return, modifiers: [])
        case .backspace: content.keyboardShortcut(.delete, modifiers: [])
        case .clear: content.keyboardShortcut(.escape, modifiers: [])
        case .insert(let text, _) where text.count == 1:
            content.keyboardShortcut(KeyEquivalent(Character(text)), modifiers: [])
        default: content
        }
        #else
        content
        #endif
    }
}

struct KeyStyle: ButtonStyle {
    let role: Keypad.Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var background: Color {
        switch role {
        case .digit: return Color.gray.opacity(0.28)
        case .op: return Color.orange.opacity(0.85)
        case .equals: return Color.accentColor
        case .action: return Color.gray.opacity(0.45)
        case .prefix: return Color.teal.opacity(0.35)
        case .function: return Color.gray.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch role {
        case .op, .equals: return .white
        default: return .primary
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
