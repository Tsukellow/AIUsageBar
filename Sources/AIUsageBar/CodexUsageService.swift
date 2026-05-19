import Foundation

struct CodexAuthState: Decodable, Sendable {
    struct Tokens: Decodable, Sendable {
        let accessToken: String?
        let refreshToken: String?
        let accountID: String?
        let idToken: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accountID = "account_id"
            case idToken = "id_token"
        }
    }

    let openAIAPIKey: String?
    let authMode: String?
    let lastRefresh: String?
    let tokens: Tokens?

    private enum CodingKeys: String, CodingKey {
        case openAIAPIKey = "OPENAI_API_KEY"
        case authMode = "auth_mode"
        case lastRefresh = "last_refresh"
        case tokens
    }

    var oauthCredentials: CodexOAuthCredentials? {
        if let accessToken = self.tokens?.accessToken, !accessToken.isEmpty {
            return CodexOAuthCredentials(
                accessToken: accessToken,
                accountID: self.tokens?.accountID
            )
        }

        if let apiKey = self.openAIAPIKey, !apiKey.isEmpty {
            return CodexOAuthCredentials(
                accessToken: apiKey,
                accountID: self.tokens?.accountID
            )
        }

        return nil
    }
}

enum CodexUsageError: LocalizedError {
    case missingAuthState(String)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case let .missingAuthState(path):
            return "Codex auth.json not found at \(path)"
        case .missingCredentials:
            return "No Codex OAuth credentials found in auth.json."
        }
    }
}

actor CodexUsageService {
    private let fileManager = FileManager.default
    private let liveProvider: any CodexLiveUsageProviding
    private let homeURL: URL

    init(
        liveProvider: (any CodexLiveUsageProviding)? = nil,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.homeURL = homeURL
        let codexHomeURL: URL
        if let customHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !customHome.isEmpty {
            codexHomeURL = URL(fileURLWithPath: customHome, isDirectory: true)
        } else {
            codexHomeURL = homeURL.appendingPathComponent(".codex", isDirectory: true)
        }
        self.liveProvider = liveProvider ?? CodexOAuthLiveUsageProvider(codexHomeURL: codexHomeURL)
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let authState = try self.loadRequiredAuthState()
        let rateLimits = try await self.fetchRequiredLiveUsage(authState: authState)

        return UsageSnapshot(
            refreshedAt: Date(),
            identity: self.makeIdentity(from: authState),
            rateLimits: rateLimits
        )
    }

    private func loadRequiredAuthState() throws -> CodexAuthState {
        let authURL = self.codexHomeURL.appendingPathComponent("auth.json")
        guard self.fileManager.fileExists(atPath: authURL.path) else {
            throw CodexUsageError.missingAuthState(authURL.path)
        }

        let data = try Data(contentsOf: authURL)
        let authState = try JSONDecoder().decode(CodexAuthState.self, from: data)
        guard authState.oauthCredentials != nil else {
            throw CodexUsageError.missingCredentials
        }
        return authState
    }

    private func fetchRequiredLiveUsage(authState: CodexAuthState) async throws -> RateLimitSnapshot {
        guard let rateLimits = try await self.liveProvider.fetchLiveUsage(auth: authState) else {
            throw CodexUsageError.missingCredentials
        }
        return rateLimits
    }

    private func makeIdentity(from authState: CodexAuthState?) -> CodexIdentity? {
        guard let authState else {
            return nil
        }

        let claims = authState.tokens?.idToken.flatMap(Self.decodeJWTClaims)
        let email = Self.firstStringValue(for: ["email", "preferred_username"], in: claims)

        return CodexIdentity(
            email: email,
            accountID: authState.tokens?.accountID,
            authMode: authState.authMode
        )
    }

    private var codexHomeURL: URL {
        if let customHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !customHome.isEmpty {
            return URL(fileURLWithPath: customHome, isDirectory: true)
        }
        return self.homeURL.appendingPathComponent(".codex", isDirectory: true)
    }

    private static func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else {
            return nil
        }

        var payload = String(segments[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
        payload = payload.replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private static func firstStringValue(for keys: [String], in object: [String: Any]?) -> String? {
        guard let object else {
            return nil
        }

        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }

        for value in object.values {
            if let nested = value as? [String: Any], let candidate = self.firstStringValue(for: keys, in: nested) {
                return candidate
            }
        }

        return nil
    }
}
