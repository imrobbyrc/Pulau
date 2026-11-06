import AppKit
import CryptoKit
import Foundation
import Network
import Security

public struct CodexTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let accountID: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, accountID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }
}

public enum CodexAuthError: Error {
    case missingCredentials
    case randomGenerationFailed(OSStatus)
    case listenerFailed
    case browserFailed
    case timedOut
    case invalidCallback
    case authorizationDenied
    case tokenRequestFailed(Int)
    case invalidTokenResponse
}

public actor CodexAuth {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let redirectURI = "http://localhost:1455/callback"
    private var attempt: LoopbackAttempt?
    private var signInTask: Task<CodexTokens, Error>?
    private var refreshTask: (id: UUID, task: Task<CodexTokens, Error>)?
    private var generation = 0
    private let keychain = CodexTokenKeychain()
    public private(set) var accountID: String?

    public init() {}

    public func hasCredentials() async throws -> Bool {
        let tokens = try keychain.load()
        accountID = tokens?.accountID
        return tokens != nil
    }

    public func signOut() async throws {
        generation += 1
        signInTask?.cancel()
        refreshTask?.task.cancel()
        refreshTask = nil
        let previousAttempt = attempt
        attempt = nil
        signInTask = nil
        accountID = nil
        try keychain.delete()
        if let previousAttempt { await previousAttempt.finish(.failure(CancellationError())) }
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens = try keychain.load() else { throw CodexAuthError.missingCredentials }
        if !forceRefresh && tokens.expiresAt.timeIntervalSinceNow > 300 {
            accountID = tokens.accountID
            return tokens.accessToken
        }
        let currentGeneration = generation
        let flight: (id: UUID, task: Task<CodexTokens, Error>)
        if let existing = refreshTask {
            flight = existing
        } else {
            flight = (UUID(), Task {
                let refreshed = try await self.refresh(tokens)
                guard self.generation == currentGeneration else { throw CancellationError() }
                try self.keychain.save(refreshed)
                self.accountID = refreshed.accountID
                return refreshed
            })
            refreshTask = flight
        }
        do {
            let refreshed = try await flight.task.value
            guard generation == currentGeneration else { throw CancellationError() }
            if refreshTask?.id == flight.id { refreshTask = nil }
            return refreshed.accessToken
        } catch {
            if generation == currentGeneration && refreshTask?.id == flight.id { refreshTask = nil }
            throw error
        }
    }

    public func signIn() async throws {
        generation += 1
        let currentGeneration = generation
        signInTask?.cancel()
        refreshTask?.task.cancel()
        refreshTask = nil
        let previousAttempt = attempt
        attempt = nil
        signInTask = nil
        if let previousAttempt { await previousAttempt.finish(.failure(CancellationError())) }
        guard generation == currentGeneration else { throw CancellationError() }
        let verifier = try Self.makeCodeVerifier()
        let state = try Self.makeCodeVerifier()
        let loopback = try await LoopbackAttempt(state: state)
        guard generation == currentGeneration else { throw CancellationError() }
        attempt = loopback
        var url = URLComponents(string: "https://auth.openai.com/oauth/authorize")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        let authorizationURL = url.url!
        let task = Task {
            let code = try await loopback.wait(for: authorizationURL)
            try Task.checkCancellation()
            return try await self.exchange(["grant_type": "authorization_code", "code": code,
                                            "code_verifier": verifier, "redirect_uri": Self.redirectURI])
        }
        signInTask = task
        defer {
            if attempt === loopback { attempt = nil; signInTask = nil }
        }
        let tokens = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard generation == currentGeneration, attempt === loopback else { throw CancellationError() }
        try keychain.save(tokens)
        accountID = tokens.accountID
    }

    private func refresh(_ tokens: CodexTokens) async throws -> CodexTokens {
        try await exchange(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken,
                            "redirect_uri": Self.redirectURI], fallbackRefreshToken: tokens.refreshToken)
    }

    private func exchange(_ fields: [String: String], fallbackRefreshToken: String? = nil) async throws -> CodexTokens {
        var components = URLComponents()
        components.queryItems = fields.merging(["client_id": Self.clientID]) { _, new in new }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CodexAuthError.invalidTokenResponse }
        guard (200..<300).contains(response.statusCode) else { throw CodexAuthError.tokenRequestFailed(response.statusCode) }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refreshToken ?? fallbackRefreshToken,
              let accountID = Self.accountID(from: decoded.accessToken), !refresh.isEmpty,
              !decoded.accessToken.isEmpty, decoded.expiresIn > 0 else { throw CodexAuthError.invalidTokenResponse }
        return CodexTokens(accessToken: decoded.accessToken, refreshToken: refresh,
                           expiresAt: Date().addingTimeInterval(decoded.expiresIn), accountID: accountID)
    }

    nonisolated static func makeCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw CodexAuthError.randomGenerationFailed(status) }
        return base64URL(Data(bytes))
    }

    nonisolated static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    // This extracts an identifier, not a JWT signature validation.
    nonisolated static func accountID(from token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode(JWTClaims.self, from: data),
              !claims.auth.accountID.isEmpty else { return nil }
        return claims.auth.accountID
    }

    nonisolated private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }
}

private struct JWTClaims: Decodable {
    struct Auth: Decodable {
        let accountID: String
        enum CodingKeys: String, CodingKey { case accountID = "chatgpt_account_id" }
    }
    let auth: Auth
    enum CodingKeys: String, CodingKey { case auth = "https://api.openai.com/auth" }
}

struct CallbackRequestLine {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> String? {
        buffer.append(data)
        guard buffer.count <= 16384 else { throw CodexAuthError.invalidCallback }
        guard let end = buffer.range(of: Data("\r\n".utf8)) else { return nil }
        guard let line = String(data: buffer[..<end.lowerBound], encoding: .utf8) else {
            throw CodexAuthError.invalidCallback
        }
        return line
    }
}

@MainActor
private final class LoopbackAttempt {
    private let listener: NWListener
    private let state: String
    private var continuation: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var finished = false

    init(state: String) throws {
        self.state = state
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 1455)
        listener = try NWListener(using: parameters)
    }

    func wait(for url: URL) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !finished, !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError()); return
                }
                self.continuation = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            if !NSWorkspace.shared.open(url) { self.finish(.failure(CodexAuthError.browserFailed)) }
                        case .failed: self.finish(.failure(CodexAuthError.listenerFailed))
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.receive(connection) }
                }
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    self?.finish(.failure(CodexAuthError.timedOut))
                }
                listener.start(queue: .main)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { connection.cancel() }
        receiveLine(connection, parser: CallbackRequestLine())
    }

    private func receiveLine(_ connection: NWConnection, parser: CallbackRequestLine) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.finished else { connection.cancel(); return }
                var parser = parser
                let firstLine: String
                do {
                    guard let line = try parser.append(data ?? Data()) else {
                        if complete || error != nil { connection.cancel() }
                        else { self.receiveLine(connection, parser: parser) }
                        return
                    }
                    firstLine = line
                } catch { connection.cancel(); return }
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2, parts[0] == "GET",
                      let url = URLComponents(string: "http://localhost\(parts[1])"), url.path == "/callback",
                      let items = url.queryItems,
                      items.first(where: { $0.name == "state" })?.value == self.state else {
                    connection.cancel(); return
                }
                let code = items.first(where: { $0.name == "code" })?.value
                let result: Result<String, Error>
                if let code, !code.isEmpty { result = .success(code) }
                else if items.contains(where: { $0.name == "error" }) { result = .failure(CodexAuthError.authorizationDenied) }
                else { result = .failure(CodexAuthError.invalidCallback) }
                let body = "You may close this window."
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                self.finish(result)
            }
        }
    }

    func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        listener.cancel()
        timeout?.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}
