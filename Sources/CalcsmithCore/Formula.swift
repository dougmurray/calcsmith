import Foundation

/// One input variable of a solve variant.
public struct Var: Sendable, Hashable {
    public let symbol: String
    public let name: String
    public let unit: String
    public let defaultValue: Double

    public init(_ symbol: String, _ name: String, _ unit: String, _ defaultValue: Double) {
        self.symbol = symbol
        self.name = name
        self.unit = unit
        self.defaultValue = defaultValue
    }
}

/// One rearrangement of a formula — "solve for X". Tab cycles through these.
public struct Variant: Sendable {
    public let solvesFor: String
    public let expression: String
    /// Unit of the solved-for quantity.
    public let unit: String
    public let inputs: [Var]
    /// Inputs arrive in the same order as `inputs`.
    public let compute: @Sendable ([Double]) -> Double

    public init(
        solvesFor: String, expression: String, unit: String, inputs: [Var],
        compute: @escaping @Sendable ([Double]) -> Double
    ) {
        self.solvesFor = solvesFor
        self.expression = expression
        self.unit = unit
        self.inputs = inputs
        self.compute = compute
    }
}

public struct Formula: Sendable, Identifiable {
    public let name: String
    public let note: String?
    public let variants: [Variant]
    /// Set by `FormulaLibrary` when the formula is placed in a topic.
    public internal(set) var topic: String = ""

    public var id: String { "\(topic)/\(name)" }

    public init(name: String, note: String? = nil, variants: [Variant]) {
        self.name = name
        self.note = note
        self.variants = variants
    }

    /// Every symbol appearing in any variant, either as input or output.
    public var symbols: [String] {
        var seen: [String] = []
        for v in variants {
            for s in [v.solvesFor] + v.inputs.map(\.symbol) where !seen.contains(s) {
                seen.append(s)
            }
        }
        return seen
    }
}

public struct Topic: Sendable, Identifiable {
    public let name: String
    public let formulas: [Formula]
    public var id: String { name }

    public init(name: String, formulas: [Formula]) {
        self.name = name
        self.formulas = formulas.map { f in
            var f = f
            f.topic = name
            return f
        }
    }
}
