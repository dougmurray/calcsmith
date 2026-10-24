import Foundation

/// The full set of formulas, grouped by topic (ported from analog_engineer_assistant).
public enum FormulaLibrary {
    public static let topics: [Topic] = [
        conversions(),
        basics(),
        amplifiers(),
        pcbWire(),
        sensor(),
        digital(),
        adc(),
        dac(),
        multiplexer(),
        rf(),
    ]

    public static var allFormulas: [Formula] { topics.flatMap(\.formulas) }

    public static func formula(id: String) -> Formula? {
        allFormulas.first { $0.id == id }
    }

    /// Fuzzy search over formula name, topic, expressions and variable names.
    /// Returns matches ordered best-first; an empty query returns everything in library order.
    public static func search(_ query: String) -> [Formula] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allFormulas }
        return allFormulas
            .compactMap { f -> (Formula, Int)? in
                // Prefer hits on the name itself.
                if let s = FuzzyMatch.score(query: q, in: f.name) { return (f, 2 * s) }
                guard let s = FuzzyMatch.score(query: q, in: searchText(f)) else { return nil }
                return (f, s)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func searchText(_ f: Formula) -> String {
        var parts = [f.name, f.topic]
        for v in f.variants {
            parts.append(v.expression)
            parts.append(contentsOf: v.inputs.map(\.name))
        }
        return parts.joined(separator: " ")
    }
}

/// Each whitespace-separated query term must match: whole substrings (best at a word start)
/// score far above skim-style subsequence matches, where consecutive and word-start hits count more.
public enum FuzzyMatch {
    public static func score(query: String, in text: String) -> Int? {
        let lower = text.lowercased()
        let hay = Array(lower)
        // Whitespace-separated query terms must each match somewhere.
        var total = 0
        for term in query.lowercased().split(separator: " ") {
            if let r = lower.range(of: term) {
                let atWordStart = r.lowerBound == lower.startIndex
                    || !lower[lower.index(before: r.lowerBound)].isLetter
                total += atWordStart ? 200 : 120
                continue
            }
            // Scattered subsequence hits are noise; require mostly word-start/consecutive matches.
            guard let s = scoreTerm(Array(term), hay), s >= term.count * 6 else { return nil }
            total += s
        }
        return total
    }

    private static func scoreTerm(_ needle: [Character], _ hay: [Character]) -> Int? {
        var score = 0
        var hi = 0
        var prevMatch = -2
        for c in needle {
            var found = false
            while hi < hay.count {
                if hay[hi] == c {
                    score += 1
                    if hi == prevMatch + 1 { score += 5 }
                    if hi == 0 || !(hay[hi - 1].isLetter || hay[hi - 1].isNumber) { score += 8 }
                    prevMatch = hi
                    hi += 1
                    found = true
                    break
                }
                hi += 1
            }
            if !found { return nil }
        }
        return score
    }
}
