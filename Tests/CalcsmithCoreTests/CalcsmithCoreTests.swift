import Foundation
import Testing
@testable import CalcsmithCore

@Suite struct EngineeringFormatterTests {
    @Test(arguments: [
        (1e-3, "1m"), (4.7e-6, "4.7μ"), (12_000.0, "12k"), (0.0, "0"), (1.0, "1"),
        (-2.2e-9, "−2.2n"), (999.9999999, "1k"), (3.3e6, "3.3M"), (1.5e-15, "1.5f"),
        (123.456789, "123.457"), (1e33, "1e33"),
    ])
    func formats(_ value: Double, _ expected: String) {
        #expect(EngineeringFormatter.format(value) == expected)
    }

    @Test func unitsAndSeparator() {
        #expect(EngineeringFormatter.format(4700, unit: "Ω", separator: " ") == "4.7 kΩ")
        #expect(EngineeringFormatter.quantity(1.6, unit: "mm") == "1.6 mm")
        #expect(EngineeringFormatter.quantity(4700, unit: "pF") == "4700 pF")
        #expect(EngineeringFormatter.quantity(1.59e3, unit: "Hz") == "1.59 kHz")
    }

    @Test func scientific() {
        #expect(EngineeringFormatter.scientific(4.7e-6) == "4.7e-6")
        #expect(EngineeringFormatter.scientific(1234.5) == "1234.5")
    }
}

@Suite struct ExpressionEvaluatorTests {
    let calc = ExpressionEvaluator(angleMode: .degrees)

    func eval(_ s: String) throws -> Double { try calc.evaluate(s) }

    static let cases: [(String, Double)] = [
        ("1+2*3", 7), ("(1+2)*3", 9), ("2^3^2", 512), ("-2^2", -4), ("2^-1", 0.5),
        ("10/4", 2.5), ("4.7k", 4700), ("10u", 1e-5), ("3.3n*2", 6.6e-9), ("1M/1k", 1000),
        ("1e-3", 1e-3), ("2E3", 2000), ("0xFF", 255), ("0b1010", 10), ("5!", 120), ("50%", 0.5),
        ("10k||10k", 5000), ("10k ∥ 10k ∥ 10k", 10000.0 / 3), ("2π", 2 * Double.pi), ("3(4+1)", 15),
        ("sin(30)", 0.5), ("cos 60", 0.5), ("sqrt(16)", 4), ("√16", 4), ("log(1000)", 3),
        ("ln(e)", 1), ("log(8, 2)", 3), ("2×3÷4−1", 0.5), ("1/(2π·1k·1u)", 1 / (2 * Double.pi * 1e-3)),
        ("2**10", 1024), ("abs(-3)", 3), ("(1+2", 3), ("5²", 25), ("db(10)", 20), ("2pi", 2 * Double.pi),
    ]

    @Test(arguments: cases)
    func evaluates(_ expr: String, _ expected: Double) throws {
        let v = try eval(expr)
        #expect(abs(v - expected) <= 1e-12 * max(1, abs(expected)), "\(expr) = \(v)")
    }

    @Test func radians() throws {
        let v = try ExpressionEvaluator(angleMode: .radians).evaluate("sin(pi/2)")
        #expect(abs(v - 1) < 1e-15)
    }

    @Test func ansVariable() throws {
        let v = try ExpressionEvaluator(variables: ["ans": 21]).evaluate("ans*2")
        #expect(v == 42)
    }

    static let pastes: [(String, String)] = [
        ("4.7 kΩ", "4.7k"), ("4.7kΩ", "4.7k"), ("4700 pF", "4700p"), ("1.59 kHz", "1.59k"),
        ("12 codes", "12"), ("−2.2 nA", "−2.2n"), ("1e33 F", "1e33"), (" 2*pi*1k\n", "2*pi*1k"),
        ("3 dB", "3"), ("1.6 mm", "1.6"), ("4.7 k", "4.7k"), ("ans+1", "ans+1"), ("hello", "hello"),
    ]

    @Test(arguments: pastes)
    func cleansPastedText(_ pasted: String, _ expected: String) {
        #expect(ExpressionEvaluator.expression(fromPasted: pasted) == expected)
    }

    @Test(arguments: ["", "1+", "foo", "2 $ 3", "sin(1,2)", "1)"])
    func rejects(_ expr: String) {
        #expect(throws: EvaluationError.self) { try eval(expr) }
    }
}

@Suite struct FormulaSessionTests {
    func ohms() throws -> Formula {
        try #require(FormulaLibrary.allFormulas.first { $0.name == "Ohm's Law" })
    }

    @Test func parsesUnitsAndPrefixes() throws {
        #expect(try FormulaSession.parse("4.7uF", unit: "F").get() == 4.7e-6)
        #expect(try FormulaSession.parse("10 kΩ", unit: "Ω").get() == 10_000)
        #expect(try FormulaSession.parse("1.6mm", unit: "mm").get() == 1.6)
        #expect(try FormulaSession.parse("10mm", unit: "m").get() == 0.01)
    }

    @Test func tabCarriesResultIntoOldSubject() throws {
        var s = FormulaSession(formula: try ohms())
        s.inputs["I"] = "2m"
        s.inputs["R"] = "1k"
        #expect(try s.result.get() == 2)  // V = I·R
        s.cycleVariant()  // → I = V / R
        #expect(s.variant.solvesFor == "I")
        #expect(s.inputs["V"] == "2")
        #expect(abs(try s.result.get() - 2e-3) < 1e-15)
        s.cycleVariant(forward: false)
        #expect(s.variant.solvesFor == "V")
    }

    @Test func invalidInputReportsError() throws {
        var s = FormulaSession(formula: try ohms())
        s.inputs["I"] = "abc"
        #expect(throws: EvaluationError.self) { try s.result.get() }
    }
}

@Suite struct FormulaLibraryTests {
    @Test func portedEverything() {
        #expect(FormulaLibrary.topics.count == 10)
        #expect(FormulaLibrary.allFormulas.count == 104)
        #expect(FormulaLibrary.allFormulas.reduce(0) { $0 + $1.variants.count } == 166)
        #expect(Set(FormulaLibrary.allFormulas.map(\.id)).count == 104)
    }

    @Test func searchFindsByNameAndVariable() {
        #expect(FormulaLibrary.search("ohm").first?.name == "Ohm's Law")
        #expect(FormulaLibrary.search("volt div").first?.name == "Voltage Divider")
        #expect(FormulaLibrary.search("zzzzqqq").isEmpty)
        #expect(FormulaLibrary.search("").count == 104)
    }

    @Test func defaultsProduceFiniteResults() {
        for f in FormulaLibrary.allFormulas {
            for v in f.variants {
                let r = v.compute(v.inputs.map(\.defaultValue))
                #expect(r.isFinite, "\(f.id) solve \(v.solvesFor) = \(r)")
            }
        }
    }

    /// Solve variant 0 from its defaults, then feed that answer into every other variant
    /// and check it recovers the original input. Catches mis-rearranged equations.
    @Test func variantsInvertEachOther() {
        // Variants whose output is intentionally quantized (codes, integer bits).
        let quantized: Set<String> = ["codes", "bits", "LSB"]
        var checked = 0
        for f in FormulaLibrary.allFormulas where f.variants.count > 1 {
            let base = f.variants[0]
            var known = Dictionary(base.inputs.map { ($0.symbol, $0.defaultValue) }, uniquingKeysWith: { a, _ in a })
            known[base.solvesFor] = base.compute(base.inputs.map(\.defaultValue))
            for v in f.variants.dropFirst() {
                guard let expected = known[v.solvesFor],
                      let args = Optional(v.inputs.compactMap { known[$0.symbol] }),
                      args.count == v.inputs.count,
                      !quantized.contains(v.unit), !quantized.contains(base.unit)
                else { continue }
                let got = v.compute(args)
                checked += 1
                #expect(abs(got - expected) <= 1e-6 * max(abs(expected), 1e-30),
                        "\(f.id): solve \(v.solvesFor) gave \(got), expected \(expected)")
            }
        }
        print("variant round-trips checked:", checked)
        #expect(checked > 40)
    }
}
