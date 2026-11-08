import Foundation

// Endpoints and request conventions adapted from OpenUsage (MIT), © Robin Ebers.
struct ZAIUsageClient {
    struct HTTPError: Error {
        let status: Int
        let retryAfter: TimeInterval?
    }

    func quota(apiKey: String) async throws -> Data {
        try await get("https://api.z.ai/api/monitor/usage/quota/limit", apiKey: apiKey)
    }

    func subscription(apiKey: String) async throws -> Data {
        try await get("https://api.z.ai/api/biz/subscription/list", apiKey: apiKey)
    }

    private func get(_ endpoint: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: endpoint)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPError(status: response.statusCode, retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        }
        return data
    }

    private static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}
