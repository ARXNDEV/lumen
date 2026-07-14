import Foundation

/// Small recursive-descent math parser (safer than NSExpression, which can
/// raise Objective-C exceptions and crash on malformed input).
enum Calculator {
    static func isMathExpression(_ s: String) -> Bool {
        let allowed = Set("0123456789.+-*/%^() ")
        guard !s.isEmpty, s.allSatisfy({ allowed.contains($0) }) else { return false }
        guard s.contains(where: { $0.isNumber }) else { return false }
        guard s.contains(where: { "+-*/%^".contains($0) }) else { return false }
        return true
    }

    static func evaluate(_ s: String) -> Double? {
        var parser = Parser(Array(s.replacingOccurrences(of: " ", with: "")))
        guard let v = parser.parseExpression(), parser.atEnd, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        if v.rounded() == v && abs(v) < 1e15 {
            return String(Int64(v))
        }
        return String(format: "%.10g", v)
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        init(_ c: [Character]) { chars = c }

        var atEnd: Bool { i >= chars.count }

        func peek() -> Character? { i < chars.count ? chars[i] : nil }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                i += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = (op == "+") ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                i += 1
                guard let rhs = parseFactor() else { return nil }
                switch op {
                case "*": lhs *= rhs
                case "/": lhs /= rhs
                default: lhs = lhs.truncatingRemainder(dividingBy: rhs)
                }
            }
            return lhs
        }

        mutating func parseFactor() -> Double? {
            guard let base = parseUnary() else { return nil }
            if peek() == "^" {
                i += 1
                guard let exp = parseFactor() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            if peek() == "-" {
                i += 1
                return parseUnary().map { -$0 }
            }
            if peek() == "+" {
                i += 1
                return parseUnary()
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Double? {
            if peek() == "(" {
                i += 1
                let v = parseExpression()
                guard peek() == ")" else { return nil }
                i += 1
                return v
            }
            var num = ""
            while let c = peek(), c.isNumber || c == "." {
                num.append(c)
                i += 1
            }
            return Double(num)
        }
    }
}
