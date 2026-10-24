import Foundation

/// Rust-style `f64` method names, so the formula closures ported from
/// analog_engineer_assistant read the same as the original source.
extension Double {
    @inline(__always) func sqrt() -> Double { Foundation.sqrt(self) }
    @inline(__always) func cbrt() -> Double { Foundation.cbrt(self) }
    @inline(__always) func ln() -> Double { Foundation.log(self) }
    @inline(__always) func log10() -> Double { Foundation.log10(self) }
    @inline(__always) func log2() -> Double { Foundation.log2(self) }
    @inline(__always) func exp() -> Double { Foundation.exp(self) }
    @inline(__always) func abs() -> Double { Swift.abs(self) }
    @inline(__always) func powi(_ n: Int) -> Double { Foundation.pow(self, Double(n)) }
    @inline(__always) func powf(_ n: Double) -> Double { Foundation.pow(self, n) }
    // Rust's f64::min/max ignore NaN operands; Double.minimum/maximum match that.
    @inline(__always) func min(_ other: Double) -> Double { Double.minimum(self, other) }
    @inline(__always) func max(_ other: Double) -> Double { Double.maximum(self, other) }
}
