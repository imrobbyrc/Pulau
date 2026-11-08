import Foundation

// Request conventions adapted from OpenUsage (MIT), © Robin Ebers.
struct CodexUsageClient {
    struct HTTPError: Error {
        let status: Int
        let retryAfter: TimeInterval?
    }
    struct Response {
        let body: Data
        let primaryHeader: String?
        let secondaryHeader: String?
    }

    func usage(auth: CodexAuth) async throws -> CodexUsageMapper.Usage {
        for attempt in 0...1 {
            let token = try await auth.accessToken(forceRefresh: attempt == 1)
            do {
                let response = try await request(accessToken: token, accountID: await auth.accountID)
                return try CodexUsageMapper.usage(response.body, primaryHeader: response.primaryHeader, secondaryHeader: response.secondaryHeader)
            } catch let error as HTTPError where error.status == 401 && attempt == 0 {
                continue
            } catch CodexUsageMapper.ParseError.bodyError(let code) where code == 401 && attempt == 0 {
                continue
            }
        }
        throw HTTPError(status: 401, retryAfter: nil)
    }

    private func request(accessToken: String, accountID: String?) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID { request.setValue(accountID, forHTTPHeaderField: "chatgpt_account_id") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPError(status: response.statusCode, retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        }
        return Response(body: data, primaryHeader: response.value(forHTTPHeaderField: "x-codex-primary-used-percent"), secondaryHeader: response.value(forHTTPHeaderField: "x-codex-secondary-used-percent"))
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
