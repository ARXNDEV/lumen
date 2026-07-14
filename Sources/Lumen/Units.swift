import Foundation

/// Unit conversions: "10 km to mi", "72 f to c", "5 kg in lb", "2 gb to mb".
enum Units {
    // Factor tables: value in base unit.
    private static let length: [String: Double] = [
        "m": 1, "meter": 1, "meters": 1, "km": 1000, "cm": 0.01, "mm": 0.001,
        "mi": 1609.344, "mile": 1609.344, "miles": 1609.344,
        "ft": 0.3048, "feet": 0.3048, "foot": 0.3048,
        "in": 0.0254, "inch": 0.0254, "inches": 0.0254,
        "yd": 0.9144, "yard": 0.9144, "yards": 0.9144,
    ]
    private static let mass: [String: Double] = [
        "kg": 1, "g": 0.001, "mg": 0.000001, "t": 1000, "ton": 1000,
        "lb": 0.45359237, "lbs": 0.45359237, "pound": 0.45359237, "pounds": 0.45359237,
        "oz": 0.028349523,
    ]
    private static let data: [String: Double] = [
        "b": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12, "pb": 1e15,
    ]
    private static let time: [String: Double] = [
        "s": 1, "sec": 1, "seconds": 1, "min": 60, "minute": 60, "minutes": 60,
        "h": 3600, "hr": 3600, "hour": 3600, "hours": 3600,
        "d": 86400, "day": 86400, "days": 86400,
        "wk": 604800, "week": 604800, "weeks": 604800,
    ]
    private static let tables = [length, mass, data, time]

    /// Returns a formatted conversion, e.g. "10 km = 6.2137 mi", or nil.
    /// Uses proper capture groups so "10 cm to in" works ("in" is both the
    /// inch unit and a connector word).
    static func convert(_ query: String) -> String? {
        let pattern = #"^\s*(\d+(?:\.\d+)?)\s*([a-zA-Z°]+)\s+(?:to|in|as)\s+([a-zA-Z°]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let valueRange = Range(m.range(at: 1), in: query),
              let fromRange = Range(m.range(at: 2), in: query),
              let toRange = Range(m.range(at: 3), in: query),
              let v = Double(query[valueRange])
        else { return nil }

        let fromUnit = query[fromRange].lowercased().replacingOccurrences(of: "°", with: "")
        let toUnit = query[toRange].lowercased().replacingOccurrences(of: "°", with: "")
        guard !fromUnit.isEmpty, !toUnit.isEmpty else { return nil }

        // Temperature (non-linear)
        if let result = convertTemperature(v, from: fromUnit, to: toUnit) {
            return result
        }

        for table in tables {
            if let f = table[fromUnit], let t = table[toUnit] {
                let converted = v * f / t
                return "\(trim(v)) \(fromUnit) = \(trim(converted)) \(toUnit)"
            }
        }
        return nil
    }

    private static func convertTemperature(_ v: Double, from: String, to: String) -> String? {
        let temps = ["c", "celsius", "f", "fahrenheit", "k", "kelvin"]
        guard temps.contains(from), temps.contains(to) else { return nil }

        let celsius: Double
        switch from.first {
        case "c": celsius = v
        case "f": celsius = (v - 32) * 5 / 9
        default: celsius = v - 273.15
        }
        let result: Double
        switch to.first {
        case "c": result = celsius
        case "f": result = celsius * 9 / 5 + 32
        default: result = celsius + 273.15
        }
        return "\(trim(v))°\(from.prefix(1).uppercased()) = \(trim(result))°\(to.prefix(1).uppercased())"
    }

    private static func trim(_ v: Double) -> String {
        if v.rounded() == v && abs(v) < 1e15 {
            return String(Int64(v))
        }
        return String(format: "%.4g", v)
    }
}
