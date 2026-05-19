import Foundation

enum ClaudeUsageError: LocalizedError {
    case noCookie
    case noOrgId
    case unauthorized
    case invalidResponse
    case serverError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .noCookie:
            return "No Claude session cookie configured. Paste your cookie in Settings."
        case .noOrgId:
            return "Could not determine Claude organization ID from cookie."
        case .unauthorized:
            return "Claude session cookie expired. Copy a fresh cookie from claude.ai."
        case .invalidResponse:
            return "Invalid response from Claude usage endpoint."
        case let .serverError(code, body):
            if let body, !body.isEmpty {
                return "Claude usage endpoint returned HTTP \(code): \(body)"
            }
            return "Claude usage endpoint returned HTTP \(code)."
        }
    }
}

actor ClaudeUsageService {
    private let session: URLSession
    private let iso8601Formatter: ISO8601DateFormatter

    init(session: URLSession = NetworkSession.shared) {
        self.session = session
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601Formatter = formatter
    }

    /// Fetches usage from the API and builds a snapshot.
    func fetchSnapshot() async throws -> ClaudeUsageSnapshot {
        let cookie = AppSettings.claudeSessionCookie
        guard !cookie.isEmpty else {
            throw ClaudeUsageError.noCookie
        }

        let orgId = try await self.resolveOrgId(cookie: cookie)
        let response = try await self.fetchUsage(orgId: orgId, cookie: cookie)
        return self.makeSnapshot(from: response)
    }

    // MARK: - Org ID resolution

    private func resolveOrgId(cookie: String) async throws -> String {
        // Try extracting from cookie directly
        if let orgId = Self.extractOrgId(fromCookie: cookie) {
            return orgId
        }

        // Fallback: call bootstrap API
        return try await self.fetchOrgIdFromBootstrap(cookie: cookie)
    }

    static func extractOrgId(fromCookie cookie: String) -> String? {
        for part in cookie.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                let value = trimmed.replacingOccurrences(of: "lastActiveOrg=", with: "")
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func fetchOrgIdFromBootstrap(cookie: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/bootstrap")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        Self.setCommonHeaders(on: &request, cookie: cookie)

        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClaudeUsageError.unauthorized
        }

        guard http.statusCode == 200 else {
            throw ClaudeUsageError.serverError(http.statusCode, String(data: data, encoding: .utf8))
        }

        guard let orgId = try JSONDecoder().decode(BootstrapResponse.self, from: data).orgId else {
            throw ClaudeUsageError.noOrgId
        }
        return orgId
    }

    // MARK: - Usage fetch

    private func fetchUsage(orgId: String, cookie: String) async throws -> ClaudeUsageResponse {
        let urlString = "https://claude.ai/api/organizations/\(orgId)/usage"
        guard let url = URL(string: urlString) else {
            throw ClaudeUsageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        Self.setCommonHeaders(on: &request, cookie: cookie)

        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        case 401, 403:
            throw ClaudeUsageError.unauthorized
        default:
            throw ClaudeUsageError.serverError(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Helpers

    private static func setCommonHeaders(on request: inout URLRequest, cookie: String) {
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
    }

    private func makeSnapshot(from response: ClaudeUsageResponse) -> ClaudeUsageSnapshot {
        let fiveHour = self.parseWindow(response.fiveHour)
        let sevenDay = self.parseWindow(response.sevenDay)

        var extraUsage: ClaudeExtraUsage?
        if let eu = response.extraUsage, eu.isEnabled == true {
            extraUsage = ClaudeExtraUsage(
                isEnabled: true,
                monthlyLimit: eu.monthlyLimit,
                usedCredits: eu.usedCredits ?? 0,
                utilization: eu.utilization
            )
        }

        return ClaudeUsageSnapshot(
            refreshedAt: Date(),
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            extraUsage: extraUsage
        )
    }

    private func parseWindow(_ payload: ClaudeUsageResponse.WindowPayload?) -> ClaudeRateLimitWindow? {
        guard let payload, let utilization = payload.utilization else {
            return nil
        }

        let resetsAt = payload.resetsAt.flatMap { self.iso8601Formatter.date(from: $0) }

        return ClaudeRateLimitWindow(
            utilization: utilization,
            resetsAt: resetsAt
        )
    }
}
