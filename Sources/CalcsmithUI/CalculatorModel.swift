import CalcsmithCore
import Foundation
import Observation

@MainActor
@Observable
public final class CalculatorModel {
    public struct Entry: Identifiable, Codable, Hashable {
        public var id = UUID()
        public let expression: String
        public let value: Double
    }

    /// The text being edited. Typing on the Mac keyboard and pressing keypad buttons both edit this.
    public var expression = ""
    public private(set) var history: [Entry] = []
    public private(set) var errorMessage: String?
    /// The last evaluated expression, shown above the result after "=".
    public private(set) var lastExpression: String?
    public private(set) var ans: Double = 0
    public var angleMode: AngleMode {
        didSet { UserDefaults.standard.set(angleMode.rawValue, forKey: Self.angleKey) }
    }
    public var significantDigits: Int {
        didSet { UserDefaults.standard.set(significantDigits, forKey: Self.digitsKey) }
    }
    /// True right after "=", until the user edits again; an operator typed now continues from `ans`.
    private(set) var justEvaluated = false

    private static let historyKey = "calculator.history"
    private static let angleKey = "calculator.angleMode"
    private static let digitsKey = "calculator.significantDigits"
    private static let historyLimit = 200

    public init() {
        let d = UserDefaults.standard
        angleMode = AngleMode(rawValue: d.string(forKey: Self.angleKey) ?? "") ?? .degrees
        let digits = d.integer(forKey: Self.digitsKey)
        significantDigits = digits == 0 ? 6 : digits
        if let data = d.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            history = saved
            ans = saved.last?.value ?? 0
        }
    }

    private var evaluator: ExpressionEvaluator {
        ExpressionEvaluator(angleMode: angleMode, variables: ["ans": ans, "Ans": ans])
    }

    /// Live result of the expression as typed, or the last answer after "=".
    public var displayValue: Double? {
        if expression.trimmingCharacters(in: .whitespaces).isEmpty {
            return lastExpression == nil ? nil : ans
        }
        return try? evaluator.evaluate(expression)
    }

    /// Whether `displayValue` is a not-yet-committed preview of the typed expression.
    public var isPreview: Bool { !expression.trimmingCharacters(in: .whitespaces).isEmpty }

    public func format(_ value: Double) -> String {
        EngineeringFormatter.format(value, significantDigits: significantDigits)
    }

    // MARK: Editing

    private static let continuationOperators: Set<Character> = ["+", "-", "−", "*", "×", "/", "÷", "^", "!", "%", "∥", "|", "²", "³"]

    /// Call when the text field changes. Implements "operator after = continues from ans"
    /// and treats a typed "=" as evaluate.
    public func textDidChange(from old: String) {
        errorMessage = nil
        if expression.hasSuffix("=") {
            expression.removeLast()
            evaluate()
            return
        }
        if justEvaluated, old.isEmpty, expression.count == 1,
           let c = expression.first, Self.continuationOperators.contains(c) {
            expression = "ans" + expression
        }
        justEvaluated = false
    }

    /// - Parameter separateFromNumber: for constants and functions — after a digit or ")"
    ///   an explicit "×" is inserted, so "2" then "e" reads 2×e rather than an exponent.
    public func insert(_ text: String, separateFromNumber: Bool = false) {
        let old = expression
        if separateFromNumber, let last = expression.last, last.isNumber || last == ")" {
            expression += "×"
        }
        expression += text
        textDidChange(from: old)
    }

    public func backspace() {
        errorMessage = nil
        justEvaluated = false
        // Remove whole function names like "sin(" in one press.
        for name in ExpressionEvaluator.functionNames.sorted(by: { $0.count > $1.count })
        where expression.hasSuffix(name + "(") {
            expression.removeLast(name.count + 1)
            return
        }
        if expression.hasSuffix("ans") { expression.removeLast(3); return }
        if !expression.isEmpty { expression.removeLast() }
    }

    public func clear() {
        expression = ""
        errorMessage = nil
        lastExpression = nil
        justEvaluated = false
    }

    public func evaluate() {
        let text = expression.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        do {
            let value = try evaluator.evaluate(text)
            ans = value
            lastExpression = text
            history.append(Entry(expression: text, value: value))
            if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
            saveHistory()
            expression = ""
            errorMessage = nil
            justEvaluated = true
        } catch {
            errorMessage = error.message
        }
    }

    /// Re-load a previous expression for editing.
    public func recall(_ entry: Entry) {
        expression = entry.expression
        errorMessage = nil
        justEvaluated = false
    }

    /// Insert a previous result into the current expression at full precision.
    public func insertValue(_ value: Double) {
        insert(EngineeringFormatter.scientific(value, significantDigits: 15), separateFromNumber: true)
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
}
