import Foundation
import Combine

@MainActor
final class CodexUsageStore: ObservableObject {
    enum SignInState { case signedOut, signingIn, signedIn, failed }
    @Published private(set) var signInState: SignInState = .signedOut
    @Published private(set) var loading = false
    @Published private(set) var fiveHourRemaining: Double?
    @Published private(set) var secondaryRemaining: Double?
    @Published private(set) var primaryResetAt: Date?
    @Published private(set) var secondaryResetAt: Date?
    @Published private(set) var planName: String?
    @Published private(set) var error: String?

    private let auth = CodexAuth()
    private let client = CodexUsageClient()
    private var loop: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var generation = UUID()
    private var delay: TimeInterval = 300
    private var failures = 0
    private var retryNotBefore = Date.distantPast

    init() {
        let id = generation
        Task {
            do {
                let found = try await auth.hasCredentials()
                guard generation == id else { return }
                if found { signInState = .signedIn; restart() }
            } catch {
                guard generation == id else { return }
                signInState = .failed
                self.error = "Codex: unable to read Keychain."
            }
        }
    }

    func signIn() {
        guard signInState != .signingIn else { return }
        generation = UUID()
        let id = generation
        loop?.cancel()
        signInState = .signingIn
        error = nil
        signInTask = Task {
            do {
                try await auth.signIn()
                guard !Task.isCancelled, generation == id else { return }
                signInState = .signedIn
                delay = 300; failures = 0; retryNotBefore = .distantPast
                restart()
            } catch {
                guard !Task.isCancelled, generation == id else { return }
                signInState = .failed
                self.error = "Codex: sign-in failed."
            }
        }
    }

    func signOut() {
        generation = UUID()
        let id = generation
        loop?.cancel()
        signInTask?.cancel()
        loading = false
        signInState = .signedOut
        fiveHourRemaining = nil; secondaryRemaining = nil
        primaryResetAt = nil; secondaryResetAt = nil; planName = nil; error = nil
        Task {
            do { try await auth.signOut() }
            catch { if generation == id { self.error = "Codex: unable to remove credentials." } }
        }
    }

    func refreshNow() { if signInState == .signedIn { restart() } }

    private func restart() {
        loop?.cancel()
        let id = UUID()
        generation = id
        loop = Task {
            while !Task.isCancelled {
                let wait = retryNotBefore.timeIntervalSinceNow
                if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
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
            let usage = try await client.usage(auth: auth)
            guard !Task.isCancelled, generation == id else { return }
            fiveHourRemaining = usage.primary?.remainingPercent
            secondaryRemaining = usage.secondary?.remainingPercent
            primaryResetAt = usage.primary?.resetAt
            secondaryResetAt = usage.secondary?.resetAt
            planName = usage.planName
            error = nil; delay = 300; failures = 0; retryNotBefore = .distantPast
        } catch {
            guard !Task.isCancelled, generation == id else { return }
            self.error = "Codex: unavailable; retrying."
            if let http = error as? CodexUsageClient.HTTPError, let retry = http.retryAfter {
                retryNotBefore = Date().addingTimeInterval(retry)
            }
            failures += 1
            delay = min(3600, 300 * pow(2, Double(min(failures - 1, 4))))
        }
    }
}
