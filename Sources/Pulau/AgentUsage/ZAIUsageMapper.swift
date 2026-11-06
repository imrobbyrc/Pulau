import Foundation

// Adapted from OpenUsage's ZAIUsageMapper (MIT), © Robin Ebers.
enum ZAIUsageMapper {
    enum Kind { case fiveHour, weekly }
    struct Limit {
        let kind: Kind
        let remainingPercent: Double
        let resetAt: Date?
    }
    enum ParseError: Error { case invalidResponse, noCodingPlan, unauthorized }

    static func quota(_ body: Data) throws -> [Limit] {
        guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw ParseError.invalidResponse
        }
        if root["success"] as? Bool == false {
            if (root["code"] as? Int) == 401 { throw ParseError.unauthorized }
            if (root["msg"] as? String)?.localizedCaseInsensitiveContains("coding plan") == true {
                throw ParseError.noCodingPlan
            }
            throw ParseError.invalidResponse
        }
        let container: [String: Any]
        if let data = root["data"] {
            guard let object = data as? [String: Any] else { throw ParseError.invalidResponse }
            container = object
        } else { container = root }
        guard let rows = container["limits"] as? [[String: Any]] else { throw ParseError.invalidResponse }
        var result: [Limit] = []
        for row in rows {
            let type = (row["type"] as? String) ?? (row["name"] as? String)
            guard type == "CREDIT_LIMIT" || type == "TOKENS_LIMIT" else { continue }
            guard let unit = number(row["unit"]), let count = number(row["number"]), count.isFinite, count > 0 else {
                throw ParseError.invalidResponse
            }
            let hours: Double
            switch unit {
            case 3: hours = count
            case 4: hours = count * 24
            case 6: hours = count * 168
            case 5: hours = count * 720
            default: continue
            }
            guard let used = number(row["percentage"]), used.isFinite else { throw ParseError.invalidResponse }
            let reset = number(row["nextResetTime"]).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            result.append(Limit(kind: hours < 24 ? .fiveHour : .weekly,
                                remainingPercent: 100 - min(100, max(0, used)), resetAt: reset))
        }
        return result
    }

    static func planName(_ body: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let list = root["data"] as? [[String: Any]],
              let name = (list.first?["productName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
