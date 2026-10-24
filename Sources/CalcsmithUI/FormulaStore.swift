import CalcsmithCore
import Foundation
import Observation

@MainActor
@Observable
public final class FormulaStore {
    public var query = ""
    public var selectedID: Formula.ID?
    /// iOS navigation stack of open formulas (macOS uses `selectedID` in a split view instead).
    public var path: [Formula.ID] = []
    /// Bumped when the inputs should take keyboard focus (e.g. Return in the search field).
    public private(set) var focusInputsRequest = 0
    /// Set alongside `focusInputsRequest`; consumed by the detail view that takes focus.
    var inputFocusPending = false
    private var sessions: [Formula.ID: FormulaSession] = [:]

    public init() {}

    public var results: [Formula] { FormulaLibrary.search(query) }

    /// Results grouped by topic, keeping library order (used when not searching).
    public var groupedResults: [(topic: String, formulas: [Formula])] {
        FormulaLibrary.topics.compactMap { topic in
            let matches = results.filter { $0.topic == topic.name }
            return matches.isEmpty ? nil : (topic.name, matches)
        }
    }

    public var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    public func session(_ formula: Formula) -> FormulaSession {
        sessions[formula.id] ?? FormulaSession(formula: formula)
    }

    public func update(_ formula: Formula, _ change: (inout FormulaSession) -> Void) {
        var s = session(formula)
        change(&s)
        sessions[formula.id] = s
    }

    /// Return in the search field: open the best match and move focus to its inputs.
    public func openTopResult() {
        guard let first = results.first else { return }
        selectedID = first.id
        #if os(iOS)
        path = [first.id]
        #endif
        requestInputFocus()
    }

    /// ↑/↓ in the search field: move the selection through the visible results.
    public func moveSelection(by delta: Int) {
        let ids = (isSearching ? results : groupedResults.flatMap(\.formulas)).map(\.id)
        guard !ids.isEmpty else { return }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? (delta > 0 ? 0 : ids.count - 1)
        selectedID = ids[next]
    }

    /// Return in the search field: open the selected (or best) match and focus its inputs.
    public func openSelectedOrTopResult() {
        if let id = selectedID, results.contains(where: { $0.id == id }) {
            requestInputFocus()
        } else {
            openTopResult()
        }
    }

    public func requestInputFocus() {
        inputFocusPending = true
        focusInputsRequest += 1
    }
}
