import Foundation

/// Formats numbers in engineering notation with SI prefixes:
/// 0.0047 → "4.7m", 4.7e-6 → "4.7μ", 12000 → "12k".
public enum EngineeringFormatter {
    /// SI prefixes indexed by exponent / 3, from 10⁻³⁰ to 10³⁰.
    static let prefixes: [Int: String] = [
        -30: "q", -27: "r", -24: "y", -21: "z", -18: "a", -15: "f", -12: "p", -9: "n",
        -6: "μ", -3: "m", 0: "", 3: "k", 6: "M", 9: "G", 12: "T", 15: "P", 18: "E",
        21: "Z", 24: "Y", 27: "R", 30: "Q",
    ]

    /// - Parameters:
    ///   - significantDigits: maximum significant digits kept (trailing zeros are trimmed).
    ///   - unit: appended after the prefix, e.g. "Ω" → "4.7 kΩ".
    ///   - separator: placed between the number and prefix+unit when either is present.
    public static func format(
        _ value: Double, significantDigits: Int = 6, unit: String = "", separator: String = ""
    ) -> String {
        guard value.isFinite else {
            if value.isNaN { return "NaN" }
            return value < 0 ? "−∞" : "∞"
        }
        if value == 0 { return unit.isEmpty ? "0" : "0\(separator)\(unit)" }

        let digits = max(1, significantDigits)
        var exp3 = Int((Foundation.log10(Swift.abs(value)) / 3).rounded(.down)) * 3
        var mantissa = value / pow(10, Double(exp3))
        var text = mantissaString(mantissa, digits: digits)
        // Rounding can carry the mantissa to 1000 (e.g. 999.9999 → "1000"); renormalize.
        if let rounded = Double(text), Swift.abs(rounded) >= 1000 {
            exp3 += 3
            mantissa = value / pow(10, Double(exp3))
            text = mantissaString(mantissa, digits: digits)
        }

        let suffix: String
        if let prefix = prefixes[exp3] {
            suffix = prefix + unit
        } else {
            suffix = "e\(exp3)" + (unit.isEmpty ? "" : " \(unit)")
        }
        if suffix.isEmpty { return text }
        return prefixes[exp3] != nil ? "\(text)\(separator)\(suffix)" : "\(text)\(suffix)"
    }

    /// Units that already carry an SI prefix; stacking another ("4.7 kpF") would be confusing,
    /// so these are shown as plain numbers.
    static let prefixedUnits: Set<String> = ["mm", "cm", "mV", "pF", "nH", "m%", "ppm"]

    /// A value with its unit, e.g. "4.7 kΩ"; dimensionless/prefixed units get plain digits.
    public static func quantity(_ value: Double, unit: String, significantDigits: Int = 6) -> String {
        if prefixedUnits.contains(unit) || ["bits", "codes", "LSB", "dB", "%"].contains(unit) {
            let a = Swift.abs(value)
            let plain = value.isFinite && (a == 0 || (a >= 1e-3 && a < 1e9))
            let num = plain
                ? mantissaString(value, digits: max(significantDigits, Int(Foundation.log10(max(a, 1))) + 1))
                : format(value, significantDigits: significantDigits)
            return "\(num) \(unit)"
        }
        return format(value, significantDigits: significantDigits, unit: unit, separator: " ")
    }

    /// Mantissa in [1, 1000) printed with `digits` significant figures, trailing zeros removed.
    private static func mantissaString(_ m: Double, digits: Int) -> String {
        let intDigits = Swift.abs(m) >= 100 ? 3 : Swift.abs(m) >= 10 ? 2 : 1
        let decimals = max(0, digits - intDigits)
        var s = String(format: "%.\(decimals)f", m)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s.replacingOccurrences(of: "-", with: "−")
    }

    /// Plain scientific notation, e.g. "4.7e-6", used as a secondary readout.
    public static func scientific(_ value: Double, significantDigits: Int = 10) -> String {
        guard value.isFinite else { return format(value) }
        let a = Swift.abs(value)
        if value == 0 { return "0" }
        if a >= 1e-4 && a < 1e12 {
            return String(format: "%.\(significantDigits)g", value)
        }
        let s = String(format: "%.\(significantDigits - 1)e", value)
        // Trim mantissa trailing zeros: 4.700000000e-06 → 4.7e-6
        guard let eIdx = s.firstIndex(of: "e") else { return s }
        var mant = String(s[..<eIdx])
        if mant.contains(".") {
            while mant.hasSuffix("0") { mant.removeLast() }
            if mant.hasSuffix(".") { mant.removeLast() }
        }
        let expPart = Int(s[s.index(after: eIdx)...]) ?? 0
        return "\(mant)e\(expPart)"
    }
}
