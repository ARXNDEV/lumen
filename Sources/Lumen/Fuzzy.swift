import Foundation

enum Fuzzy {
    /// Subsequence fuzzy match. Returns nil when the query doesn't match,
    /// otherwise a score roughly in 0...1.5 (higher is better).
    /// Bonuses for prefix matches, word-boundary matches and consecutive runs.
    static func score(_ query: String, _ candidate: String) -> Double? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty, q.count <= c.count else { return nil }

        var qi = 0
        var pts = 0.0
        var lastMatch = -2

        for i in 0..<c.count {
            guard qi < q.count else { break }
            if c[i] == q[qi] {
                var p = 1.0
                if i == 0 {
                    p += 2.5
                } else if !(c[i - 1].isLetter || c[i - 1].isNumber) {
                    p += 1.5
                }
                if lastMatch == i - 1 { p += 1.0 }
                pts += p
                lastMatch = i
                qi += 1
            }
        }

        guard qi == q.count else { return nil }

        let maxPts = 2.5 + Double(max(q.count - 1, 0)) * 2.0 + 1.0
        var s = pts / maxPts
        s -= Double(c.count) * 0.005
        if candidate.lowercased().hasPrefix(query.lowercased()) { s += 0.35 }
        return max(s, 0.01)
    }
}
