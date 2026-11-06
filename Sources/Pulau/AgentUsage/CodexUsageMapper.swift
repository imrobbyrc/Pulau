import Foundation

// Window and plan mapping adapted from OpenUsage (MIT), © Robin Ebers.
enum CodexUsageMapper {
    struct Window {
        let remainingPercent: Double
        let resetAt: Date?
    }
    struct Usage {
        let primary: Window?
        let secondary: Window?
        let planName: String?
    }
    enum ParseError: Error { case invalidResponse, bodyError(Int?) }

    static func usage(_ data: Data, primaryHeader: String? = nil, secondaryHeader: String? = nil, now: Date = Date()) throws -> Usage {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.invalidResponse }
        let code = number(body["code"]).flatMap { $0.isFinite && $0 >= 400 && $0 <= 999 ? Int($0) : nil }
        if body["error"] != nil && !(body["error"] is NSNull) || body["success"] as? Bool == false || code != nil {
            throw ParseError.bodyError(code)
        }
        let limits = body["rate_limit"] as? [String: Any]
        let slots: [([String: Any], Double?)?] = [(limits?["primary_window"], primaryHeader), (limits?["secondary_window"], secondaryHeader)].map { raw, header in
            let headerValue = number(header)
            guard let window = raw as? [String: Any] ?? (headerValue == nil ? nil : [:]) else { return nil }
            return (window, number(window["used_percent"]) ?? headerValue)
        }
        func window(_ index: Int, period: Double) -> Window? {
            let exact = slots.compactMap { $0 }.first { number($0.0["limit_window_seconds"]) == period }
            let fallback = slots[index].flatMap { candidate -> ([String: Any], Double?)? in
                if let seconds = number(candidate.0["limit_window_seconds"]), seconds == 18000 || seconds == 604800 { return nil }
                return candidate
            }
            guard let (source, used) = exact ?? fallback, let used, used.isFinite else { return nil }
            let reset: Date?
            if let timestamp = number(source["reset_at"]), timestamp.isFinite { reset = Date(timeIntervalSince1970: timestamp) }
            else if let after = number(source["reset_after_seconds"]), after.isFinite { reset = now.addingTimeInterval(after) }
            else { reset = nil }
            return Window(remainingPercent: 100 - min(100, max(0, used)), resetAt: reset)
        }
        let primary = window(0, period: 18000), secondary = window(1, period: 604800)
        guard primary != nil || secondary != nil else { throw ParseError.invalidResponse }
        return Usage(primary: primary, secondary: secondary, planName: planName(body["plan_type"]))
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func planName(_ value: Any?) -> String? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "prolite": return "Pro 100"
        case "pro": return "Pro 200"
        case "promax": return "Pro 500"
        case "self_serve_business_prolite": return "Business Premium"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
