import Foundation

protocol CodexLiveUsageProviding: Sendable {
    func fetchLiveUsage(auth: CodexAuthState?) async throws -> RateLimitSnapshot?
}

enum CodexOAuthError: LocalizedError {
    case unauthorized
    case invalidResponse
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Codex OAuth token expired or invalid. Refresh Codex from the terminal; AIUsageBar does not rewrite auth.json."
        case .invalidResponse:
            return "Invalid response from the Codex usage endpoint."
        case let .serverError(code, body):
            if let body, !body.isEmpty {
                return "Codex usage endpoint returned HTTP \(code): \(body)"
            }
            return "Codex usage endpoint returned HTTP \(code)."
        }
    }
}

actor CodexOAuthLiveUsageProvider: CodexLiveUsageProviding {
    private let configFileURL: URL
    private let session: URLSession
    private let creditFormatter: NumberFormatter

    init(
        codexHomeURL: URL,
        session: URLSession = NetworkSession.shared
    ) {
        self.configFileURL = codexHomeURL.appendingPathComponent("config.toml")
        self.session = session

        let creditFormatter = NumberFormatter()
        creditFormatter.numberStyle = .decimal
        creditFormatter.maximumFractionDigits = 2
        creditFormatter.minimumFractionDigits = 0
        self.creditFormatter = creditFormatter
    }

    func fetchLiveUsage(auth: CodexAuthState?) async throws -> RateLimitSnapshot? {
        guard let credentials = auth?.oauthCredentials else {
            return nil
        }

        let response = try await self.fetchUsage(credentials: credentials)
        return self.makeSnapshot(from: response)
    }

    private func fetchUsage(credentials: CodexOAuthCredentials) async throws -> CodexUsageResponse {
        var request = URLRequest(url: try self.resolveUsageURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("AIUsageBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexOAuthError.invalidResponse
        }

        switch http.statusCode {
        case 200 ... 299:
            do {
                return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            } catch {
                throw CodexOAuthError.invalidResponse
            }
        case 401, 403:
            throw CodexOAuthError.unauthorized
        default:
            let body = String(data: data, encoding: .utf8)
            throw CodexOAuthError.serverError(http.statusCode, body)
        }
    }

    private func makeSnapshot(from response: CodexUsageResponse) -> RateLimitSnapshot? {
        let creditsRemaining: String?
        if response.credits?.unlimited == true {
            creditsRemaining = "Unlimited"
        } else if let balance = response.credits?.balance, balance > 0 {
            creditsRemaining = self.creditFormatter.string(from: NSNumber(value: balance))
        } else if response.credits?.hasCredits == true {
            creditsRemaining = "Available"
        } else {
            creditsRemaining = nil
        }

        return RateLimitSnapshot(
            fiveHourRemainingPercent: response.rateLimit?.primaryWindow.map { max(0, 100 - Double($0.usedPercent)) },
            fiveHourResetsAt: response.rateLimit?.primaryWindow.map { Date(timeIntervalSince1970: Double($0.resetAt)) },
            weeklyRemainingPercent: response.rateLimit?.secondaryWindow.map { max(0, 100 - Double($0.usedPercent)) },
            weeklyResetsAt: response.rateLimit?.secondaryWindow.map { Date(timeIntervalSince1970: Double($0.resetAt)) },
            creditsRemaining: creditsRemaining,
            sourceLabel: "Codex OAuth usage API"
        )
    }

    private func resolveUsageURL() throws -> URL {
        let baseURL = self.resolveChatGPTBaseURL()
        let normalized = Self.normalizeChatGPTBaseURL(baseURL)
        let path = normalized.contains("/backend-api") ? "/wham/usage" : "/api/codex/usage"
        guard let url = URL(string: normalized + path) else {
            throw CodexOAuthError.invalidResponse
        }
        return url
    }

    private func resolveChatGPTBaseURL() -> String {
        guard let contents = try? String(contentsOf: self.configFileURL, encoding: .utf8),
              let configured = Self.parseChatGPTBaseURL(from: contents)
        else {
            return "https://chatgpt.com/backend-api/"
        }
        return configured
    }

    private static func normalizeChatGPTBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = "https://chatgpt.com/backend-api/"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if (trimmed.hasPrefix("https://chatgpt.com") || trimmed.hasPrefix("https://chat.openai.com")) && !trimmed.contains("/backend-api") {
            trimmed += "/backend-api"
        }
        return trimmed
    }

    private static func parseChatGPTBaseURL(from contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "chatgpt_base_url" else {
                continue
            }

            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

}

struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let accountID: String?
}

private struct CodexUsageResponse: Decodable, Sendable {
    let rateLimit: RateLimitDetails?
    let credits: CreditDetails?

    private enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case credits
    }

    struct RateLimitDetails: Decodable, Sendable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        private enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WindowSnapshot: Decodable, Sendable {
        let usedPercent: Int
        let resetAt: Int
        let limitWindowSeconds: Int

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    struct CreditDetails: Decodable, Sendable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: Double?

        private enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
            self.unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false

            if let value = try? container.decode(Double.self, forKey: .balance) {
                self.balance = value
            } else if let text = try? container.decode(String.self, forKey: .balance), let value = Double(text) {
                self.balance = value
            } else {
                self.balance = nil
            }
        }
    }
}
