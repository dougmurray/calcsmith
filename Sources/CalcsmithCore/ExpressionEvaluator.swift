import Foundation

public enum AngleMode: String, Sendable, CaseIterable {
    case radians = "RAD"
    case degrees = "DEG"
}

public struct EvaluationError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Parses and evaluates calculator expressions.
///
/// Supports `+ - * / ^`, unicode `× ÷ − · √ π`, parentheses, implicit
/// multiplication (`2π`, `3(4+5)`), postfix `!` and `%`, the parallel operator
/// `||` / `∥` (R1∥R2 = R1·R2/(R1+R2)), SI-prefixed numbers (`4.7k`, `10u`, `3.3n`),
/// scientific notation, hex (`0xFF`) and binary (`0b1010`) literals,
/// the usual scientific functions, and `ans`.
public struct ExpressionEvaluator: Sendable {
    public var angleMode: AngleMode
    public var variables: [String: Double]

    public init(angleMode: AngleMode = .radians, variables: [String: Double] = [:]) {
        self.angleMode = angleMode
        self.variables = variables
    }

    public func evaluate(_ text: String) throws(EvaluationError) -> Double {
        var p = Parser(tokens: try Lexer.tokenize(text), ctx: self)
        guard !p.tokens.isEmpty else { throw EvaluationError("Empty expression") }
        let v = try p.parseExpression()
        if let t = p.peek { throw EvaluationError("Unexpected \(t.display)") }
        return v
    }

    /// Units that may trail a pasted quantity, longest first so "codes" wins over "s".
    /// Prefixes stay attached: "4.7 pF" pastes as "4.7p".
    static let pasteUnits: [String] = [
        "V/√Hz", "V_rms", "codes", "ohms", "bits", "V/V", "W/W", "V/s", "H/m", "F/m",
        "ohm", "LSB", "ppm", "Hz", "dB", "°C", "mm", "cm", "m%", "Ω", "V", "F", "W", "s", "H", "A",
    ]

    /// Turns copied text, such as a formula result "4.7 kΩ", into something the
    /// calculator can evaluate ("4.7k"). Text that already evaluates is kept as is.
    public static func expression(fromPasted text: String) -> String {
        let t = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let probe = ExpressionEvaluator(variables: ["ans": 0, "Ans": 0])
        func evaluates(_ s: String) -> Bool { (try? probe.evaluate(s)) != nil }
        // Allow a space before a trailing SI prefix: "4.7 k" → "4.7k".
        func joinPrefix(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"(\d)\s+([fpnuμµmkMGT])$"#, with: "$1$2", options: .regularExpression)
        }
        if evaluates(t) { return t }
        for unit in pasteUnits where t.hasSuffix(unit) && t.count > unit.count {
            let candidate = joinPrefix(String(t.dropLast(unit.count)))
            if evaluates(candidate) { return candidate }
        }
        let joined = joinPrefix(t)
        return evaluates(joined) ? joined : t
    }

    public static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "τ": 2 * .pi,
        "c": 299_792_458,  // speed of light, m/s
        "q": 1.602_176_634e-19,  // elementary charge, C
        "kB": 1.380_649e-23,  // Boltzmann constant, J/K
        "h": 6.626_070_15e-34,  // Planck constant, J·s
        "eps0": 8.854_187_8128e-12,  // vacuum permittivity, F/m
        "mu0": 1.256_637_062_12e-6,  // vacuum permeability, H/m
    ]

    public static let functionNames: [String] = [
        "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
        "asinh", "acosh", "atanh", "sqrt", "cbrt", "abs", "exp", "ln", "log",
        "log2", "floor", "ceil", "round", "atan2", "min", "max", "mod", "db", "idb",
    ]

    fileprivate func call(_ name: String, _ args: [Double]) throws(EvaluationError) -> Double {
        let toRad = angleMode == .degrees ? Double.pi / 180 : 1
        let fromRad = 1 / toRad
        func one(_ f: (Double) -> Double) throws(EvaluationError) -> Double {
            guard args.count == 1 else { throw EvaluationError("\(name)() takes 1 argument") }
            return f(args[0])
        }
        func two(_ f: (Double, Double) -> Double) throws(EvaluationError) -> Double {
            guard args.count == 2 else { throw EvaluationError("\(name)() takes 2 arguments") }
            return f(args[0], args[1])
        }
        switch name {
        case "sin": return try one { Foundation.sin($0 * toRad) }
        case "cos": return try one { Foundation.cos($0 * toRad) }
        case "tan": return try one { Foundation.tan($0 * toRad) }
        case "asin": return try one { Foundation.asin($0) * fromRad }
        case "acos": return try one { Foundation.acos($0) * fromRad }
        case "atan": return try one { Foundation.atan($0) * fromRad }
        case "atan2": return try two { Foundation.atan2($0, $1) * fromRad }
        case "sinh": return try one(Foundation.sinh)
        case "cosh": return try one(Foundation.cosh)
        case "tanh": return try one(Foundation.tanh)
        case "asinh": return try one(Foundation.asinh)
        case "acosh": return try one(Foundation.acosh)
        case "atanh": return try one(Foundation.atanh)
        case "sqrt": return try one(Foundation.sqrt)
        case "cbrt": return try one(Foundation.cbrt)
        case "abs": return try one(Swift.abs)
        case "exp": return try one(Foundation.exp)
        case "ln": return try one(Foundation.log)
        case "log":
            if args.count == 2 { return Foundation.log(args[0]) / Foundation.log(args[1]) }
            return try one(Foundation.log10)
        case "log2": return try one(Foundation.log2)
        case "floor": return try one(Foundation.floor)
        case "ceil": return try one(Foundation.ceil)
        case "round": return try one { $0.rounded() }
        case "min": return try two { Swift.min($0, $1) }
        case "max": return try two { Swift.max($0, $1) }
        case "mod": return try two { Foundation.fmod($0, $1) }
        case "db": return try one { 20 * Foundation.log10($0) }  // voltage ratio → dB
        case "idb": return try one { Foundation.pow(10, $0 / 20) }  // dB → voltage ratio
        default: throw EvaluationError("Unknown function \(name)")
        }
    }
}

// MARK: - Lexer

enum Token: Equatable {
    case number(Double)
    case ident(String)
    case op(String)  // + - * / ^ ! % ∥ √
    case lparen, rparen, comma

    var display: String {
        switch self {
        case .number(let v): return EngineeringFormatter.scientific(v)
        case .ident(let s), .op(let s): return "'\(s)'"
        case .lparen: return "'('"
        case .rparen: return "')'"
        case .comma: return "','"
        }
    }
}

enum Lexer {
    static let siPrefixes: [Character: Double] = [
        "f": 1e-15, "p": 1e-12, "n": 1e-9, "u": 1e-6, "μ": 1e-6, "µ": 1e-6,
        "m": 1e-3, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "P": 1e15, "a": 1e-18,
    ]

    static func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    static func isIdentBody(_ c: Character) -> Bool { c.isLetter || isDigit(c) || c == "_" }
    // Character.isNumber also accepts "²", "½", etc.; only ASCII digits start numbers.
    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func tokenize(_ text: String) throws(EvaluationError) -> [Token] {
        let s = Array(text)
        var i = 0
        var out: [Token] = []
        while i < s.count {
            let c = s[i]
            if c.isWhitespace { i += 1; continue }

            if isDigit(c) || (c == "." && i + 1 < s.count && isDigit(s[i + 1])) {
                // Hex / binary literals
                if c == "0", i + 1 < s.count, "xXbB".contains(s[i + 1]) {
                    let radix = "xX".contains(s[i + 1]) ? 16 : 2
                    var j = i + 2
                    while j < s.count, s[j].isHexDigit { j += 1 }
                    guard let v = Int(String(s[(i + 2)..<j]), radix: radix) else {
                        throw EvaluationError("Bad \(radix == 16 ? "hex" : "binary") literal")
                    }
                    out.append(.number(Double(v)))
                    i = j
                    continue
                }
                var j = i
                while j < s.count, isDigit(s[j]) || s[j] == "." || s[j] == "_" { j += 1 }
                // Exponent: e/E followed by optional sign and at least one digit.
                if j < s.count, s[j] == "e" || s[j] == "E" {
                    var k = j + 1
                    if k < s.count, s[k] == "+" || s[k] == "-" || s[k] == "−" { k += 1 }
                    if k < s.count, isDigit(s[k]) {
                        while k < s.count, isDigit(s[k]) { k += 1 }
                        j = k
                    }
                }
                let literal = String(s[i..<j]).replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "−", with: "-")
                guard var v = Double(literal) else { throw EvaluationError("Bad number \(literal)") }
                // SI prefix glued to the number, not followed by more identifier chars.
                if j < s.count, let mult = siPrefixes[s[j]],
                   j + 1 >= s.count || !isIdentBody(s[j + 1]) {
                    v *= mult
                    j += 1
                }
                out.append(.number(v))
                i = j
                continue
            }

            if isIdentStart(c) && c != "π" && c != "τ" {
                var j = i
                while j < s.count, isIdentBody(s[j]) { j += 1 }
                out.append(.ident(String(s[i..<j])))
                i = j
                continue
            }

            switch c {
            case "π", "τ": out.append(.ident(String(c)))
            case "+": out.append(.op("+"))
            case "-", "−", "–": out.append(.op("-"))
            case "*", "×", "·", "⋅":
                if c == "*", i + 1 < s.count, s[i + 1] == "*" {
                    out.append(.op("^"))
                    i += 1
                } else {
                    out.append(.op("*"))
                }
            case "/", "÷": out.append(.op("/"))
            case "^": out.append(.op("^"))
            case "!": out.append(.op("!"))
            case "%": out.append(.op("%"))
            case "√": out.append(.op("√"))
            case "∥": out.append(.op("∥"))
            case "|":
                guard i + 1 < s.count, s[i + 1] == "|" else { throw EvaluationError("Use || for parallel") }
                out.append(.op("∥"))
                i += 1
            case "²": out.append(.op("^")); out.append(.number(2))
            case "³": out.append(.op("^")); out.append(.number(3))
            case "(", "[": out.append(.lparen)
            case ")", "]": out.append(.rparen)
            case ",", ";": out.append(.comma)
            default: throw EvaluationError("Unexpected '\(c)'")
            }
            i += 1
        }
        return out
    }
}

// MARK: - Parser (recursive descent, evaluates as it parses)

private struct Parser {
    let tokens: [Token]
    let ctx: ExpressionEvaluator
    var pos = 0

    init(tokens: [Token], ctx: ExpressionEvaluator) {
        self.tokens = tokens
        self.ctx = ctx
    }

    var peek: Token? { pos < tokens.count ? tokens[pos] : nil }
    mutating func next() -> Token? {
        defer { pos += 1 }
        return peek
    }

    // expr := term (('+'|'-') term)*
    mutating func parseExpression() throws(EvaluationError) -> Double {
        var v = try parseTerm()
        while case .op(let o) = peek, o == "+" || o == "-" {
            pos += 1
            let r = try parseTerm()
            v = o == "+" ? v + r : v - r
        }
        return v
    }

    // term := unary (('*'|'/'|'∥'|implicit) unary)*
    mutating func parseTerm() throws(EvaluationError) -> Double {
        var v = try parseUnary()
        while true {
            switch peek {
            case .op(let o) where o == "*" || o == "/" || o == "∥":
                pos += 1
                let r = try parseUnary()
                switch o {
                case "*": v *= r
                case "/": v /= r
                default: v = v * r / (v + r)
                }
            case .number, .ident, .lparen, .op("√"):
                // Implicit multiplication: 2π, 3(1+2), 2sqrt(2)
                v *= try parseUnary()
            default:
                return v
            }
        }
    }

    // unary := ('-'|'+') unary | power
    mutating func parseUnary() throws(EvaluationError) -> Double {
        if case .op(let o) = peek, o == "-" || o == "+" {
            pos += 1
            let v = try parseUnary()
            return o == "-" ? -v : v
        }
        return try parsePower()
    }

    // power := postfix ('^' unary)?   — right associative, binds tighter than unary minus
    mutating func parsePower() throws(EvaluationError) -> Double {
        let base = try parsePostfix()
        if case .op("^") = peek {
            pos += 1
            let exponent = try parseUnary()
            return Foundation.pow(base, exponent)
        }
        return base
    }

    // postfix := primary ('!' | '%')*
    mutating func parsePostfix() throws(EvaluationError) -> Double {
        var v = try parsePrimary()
        while case .op(let o) = peek, o == "!" || o == "%" {
            pos += 1
            if o == "!" {
                guard v >= 0 else { throw EvaluationError("Factorial of negative number") }
                v = Foundation.tgamma(v + 1)
            } else {
                v /= 100
            }
        }
        return v
    }

    mutating func parsePrimary() throws(EvaluationError) -> Double {
        guard let t = next() else { throw EvaluationError("Incomplete expression") }
        switch t {
        case .number(let v):
            return v
        case .op("√"):
            return Foundation.sqrt(try parsePostfix())
        case .lparen:
            let v = try parseExpression()
            // Tolerate missing closing parens at end of input, like most calculators.
            if peek == .rparen { pos += 1 } else if peek != nil { throw EvaluationError("Expected ')'") }
            return v
        case .ident(let name):
            if peek == .lparen {
                pos += 1
                var args: [Double] = []
                if peek != .rparen {
                    args.append(try parseExpression())
                    while peek == .comma {
                        pos += 1
                        args.append(try parseExpression())
                    }
                }
                if peek == .rparen { pos += 1 } else if peek != nil { throw EvaluationError("Expected ')'") }
                return try ctx.call(name.lowercased(), args)
            }
            if let v = ctx.variables[name] ?? ctx.variables[name.lowercased()] { return v }
            if let v = ExpressionEvaluator.constants[name] { return v }
            if ExpressionEvaluator.functionNames.contains(name.lowercased()) {
                // Function without parentheses: sin 30, sqrt 2
                let arg = try parsePower()
                return try ctx.call(name.lowercased(), [arg])
            }
            throw EvaluationError("Unknown name '\(name)'")
        default:
            throw EvaluationError("Unexpected \(t.display)")
        }
    }
}
