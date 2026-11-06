import Foundation
import Combine
import Security
import UserNotifications

private actor GLMKeychain {
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.robby.Pulau.glm",
         kSecAttrAccount: "api-key", kSecUseDataProtectionKeychain: true]
    }
    func load() throws -> String? {
        var q = query
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return key
    }
    func save(_ key: String) throws {
        var q = query
        let data = Data(key.utf8)
        q[kSecValueData] = data
        q[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

@MainActor
final class GLMUsageStore: ObservableObject {
    @Published private(set) var hasKey = false
    @Published private(set) var loading = false
    @Published private(set) var fiveHourRemainingPercent: Double?
    @Published private(set) var weeklyRemainingPercent: Double?
    @Published private(set) var planName: String?
    @Published private(set) var error: String?

    private let keychain = GLMKeychain()
    private let client = ZAIUsageClient()
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    private var delay: TimeInterval = 300
    private var failures = 0
    private var retryNotBefore = Date.distantPast
    // Highest severity already notified: 100 = none, 10 = low, 0 = exhausted.
    private var notifiedLevel = 100

    init() {
        let id = generation
        Task {
            do {
                let found = try await keychain.load() != nil
                guard generation == id else { return }
                hasKey = found
                if hasKey { restart() }
            } catch {
                guard generation == id else { return }
                self.error = "Unable to read GLM key from Keychain."
            }
        }
    }

    func setKey(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        loop?.cancel()
        generation = UUID()
        loading = false
        Task {
            do {
                try await keychain.save(key)
                hasKey = true
                clearUsage()
                delay = 300
                failures = 0
                retryNotBefore = .distantPast
                restart()
            } catch { self.error = "Unable to save GLM key in Keychain." }
        }
    }

    func removeKey() {
        loop?.cancel()
        generation = UUID()
        loading = false
        Task {
            do {
                try await keychain.remove()
                loop?.cancel()
                generation = UUID()
                hasKey = false
                loading = false
                clearUsage()
            } catch { self.error = "Unable to remove GLM key from Keychain." }
        }
    }

    func refreshNow() { if hasKey { restart() } }

    private func clearUsage() {
        fiveHourRemainingPercent = nil
        weeklyRemainingPercent = nil
        planName = nil
        error = nil
        notifiedLevel = 100
    }

    /// Fires a local notification once per crossing: at 10% left and at 0%.
    /// Re-arms automatically when the percentage recovers above the level.
    private func evaluateThresholds(_ percent: Double) {
        let level = percent <= 0 ? 0 : (percent <= 10 ? 10 : 100)
        guard level < notifiedLevel else {
            if level > notifiedLevel { notifiedLevel = level }
            return
        }
        notifiedLevel = level
        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "GLM 5h"
            content.body = level == 0
                ? "5-hour window exhausted."
                : String(format: "About %d%% left in the 5-hour window.", Int(percent.rounded()))
            let request = UNNotificationRequest(
                identifier: level == 0 ? "glm-5h-zero" : "glm-5h-ten",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func restart() {
        loop?.cancel()
        let id = UUID()
        generation = id
        loop = Task {
            while !Task.isCancelled {
                let wait = retryNotBefore.timeIntervalSinceNow
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                }
                await refresh(id: id)
                guard !Task.isCancelled, generation == id else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    private func refresh(id: UUID) async {
        loading = true
        defer { if generation == id { loading = false } }
        do {
            guard let key = try await keychain.load() else { throw ZAIUsageMapper.ParseError.unauthorized }
            let data = try await client.quota(apiKey: key)
            let limits = try ZAIUsageMapper.quota(data)
            guard let session = limits.first(where: { $0.kind == .fiveHour }) else {
                throw ZAIUsageMapper.ParseError.invalidResponse
            }
            var subscription: Data?
            do { subscription = try await client.subscription(apiKey: key) }
            catch let http as ZAIUsageClient.HTTPError where http.status == 429 { throw http }
            catch { subscription = nil }
            guard !Task.isCancelled, generation == id else { return }
            fiveHourRemainingPercent = session.remainingPercent
            weeklyRemainingPercent = limits.first(where: { $0.kind == .weekly })?.remainingPercent
            planName = subscription.flatMap(ZAIUsageMapper.planName)
            error = nil
            delay = 300
            failures = 0
            retryNotBefore = .distantPast
            if let percent = fiveHourRemainingPercent {
                evaluateThresholds(percent)
            }
        } catch {
            guard !Task.isCancelled, generation == id else { return }
            if let http = error as? ZAIUsageClient.HTTPError {
                self.error = http.status == 401 || http.status == 403 ? "GLM: invalid API key." : "GLM request failed (HTTP \(http.status))."
                if http.status == 429, let retry = http.retryAfter {
                    retryNotBefore = Date().addingTimeInterval(retry)
                }
            } else if case ZAIUsageMapper.ParseError.noCodingPlan = error {
                self.error = "No active GLM Coding Plan."
            } else if case ZAIUsageMapper.ParseError.unauthorized = error {
                self.error = "GLM: invalid API key."
            } else {
                self.error = "GLM usage unavailable; retrying."
            }
            failures += 1
            delay = min(3600, 300 * pow(2, Double(min(failures - 1, 4))))
        }
    }
}
