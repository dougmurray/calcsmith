import Foundation

/// Working state for one formula: which variant ("subject") is active and the
/// text typed for each variable. Values are keyed by symbol, so they carry over
/// when Tab changes the subject — and the previous result fills in the old subject.
public struct FormulaSession: Sendable {
    public let formula: Formula
    public private(set) var variantIndex: Int = 0
    /// Raw text per symbol, e.g. ["R": "4.7k"].
    public var inputs: [String: String] = [:]

    public init(formula: Formula) {
        self.formula = formula
        for v in formula.variants {
            for input in v.inputs where inputs[input.symbol] == nil {
                inputs[input.symbol] = EngineeringFormatter.format(input.defaultValue, significantDigits: 6)
            }
        }
    }

    public var variant: Variant { formula.variants[variantIndex] }

    public mutating func selectVariant(_ index: Int) {
        guard formula.variants.indices.contains(index), index != variantIndex else { return }
        // Carry the current answer into the field for the old subject.
        if case .success(let value) = result, value.isFinite {
            inputs[variant.solvesFor] = EngineeringFormatter.format(value, significantDigits: 6)
        }
        variantIndex = index
    }

    public mutating func cycleVariant(forward: Bool = true) {
        let n = formula.variants.count
        guard n > 1 else { return }
        selectVariant((variantIndex + (forward ? 1 : n - 1)) % n)
    }

    /// Parsed value of one input field.
    public func value(for input: Var) -> Result<Double, EvaluationError> {
        Self.parse(inputs[input.symbol] ?? "", unit: input.unit)
    }

    public var result: Result<Double, EvaluationError> {
        var values: [Double] = []
        for input in variant.inputs {
            switch value(for: input) {
            case .success(let v): values.append(v)
            case .failure: return .failure(EvaluationError("Enter a value for \(input.symbol)"))
            }
        }
        return .success(variant.compute(values))
    }

    /// Parses a field: any calculator expression, with SI prefixes, optionally
    /// followed by the variable's unit ("4.7uF", "10 kΩ", "2*pi*1k").
    public static func parse(_ text: String, unit: String) -> Result<Double, EvaluationError> {
        var t = text.trimmingCharacters(in: .whitespaces)
        for u in unitSpellings(unit) where !u.isEmpty && t.hasSuffix(u) && t.count > u.count {
            t = String(t.dropLast(u.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        // Allow a space before a trailing SI prefix: "10 k" → "10k".
        t = t.replacingOccurrences(of: #"(\d)\s+([fpnuμµmkKMGT])$"#, with: "$1$2", options: .regularExpression)
        do {
            return .success(try ExpressionEvaluator().evaluate(t))
        } catch {
            return .failure(error)
        }
    }

    private static func unitSpellings(_ unit: String) -> [String] {
        switch unit {
        case "Ω": return ["Ω", "ohm", "ohms", "R"]
        case "°C": return ["°C", "C"]
        default: return [unit]
        }
    }
}
