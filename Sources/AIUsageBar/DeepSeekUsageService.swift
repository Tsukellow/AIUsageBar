import Foundation

actor DeepSeekUsageService {
    private let session: URLSession
    private let baseURL = "https://platform.deepseek.com/api/v0"

    init(session: URLSession = NetworkSession.shared) {
        self.session = session
    }

    func fetchSnapshot() async throws -> DeepSeekUsageSnapshot {
        let token = AppSettings.deepSeekBearerToken
        guard !token.isEmpty else {
            throw DeepSeekUsageError.noToken
        }

        let today = Self.todayString()

        async let summaryResult = self.fetchSummary(token: token)
        async let usageResult = self.fetchUsage(token: token, month: nil, year: nil)
        async let costResult = self.fetchCost(token: token, month: nil, year: nil)

        let summary = try await summaryResult
        let usage = try await usageResult
        let cost = try await costResult

        return self.makeSnapshot(summary: summary, usage: usage, cost: cost, today: today)
    }

    // MARK: - API calls

    private func fetchSummary(token: String) async throws -> DeepSeekSummaryResponse {
        let data = try await self.get("/users/get_user_summary", token: token)
        return try self.decodeEnvelope(data)
    }

    private func fetchUsage(token: String, month: Int?, year: Int?) async throws -> DeepSeekUsageResponse {
        let today = Self.todayComponents()
        let path = "/usage/amount?month=\(month ?? today.month)&year=\(year ?? today.year)"
        let data = try await self.get(path, token: token)
        return try self.decodeEnvelope(data)
    }

    private func fetchCost(token: String, month: Int?, year: Int?) async throws -> DeepSeekCostResponse {
        let today = Self.todayComponents()
        let path = "/usage/cost?month=\(month ?? today.month)&year=\(year ?? today.year)"
        let data = try await self.get(path, token: token)
        return try self.decodeEnvelope(data)
    }

    private func get(_ path: String, token: String) async throws -> Data {
        guard let url = URL(string: "\(self.baseURL)\(path)") else {
            throw DeepSeekUsageError.invalidResponse(nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "x-app-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://platform.deepseek.com", forHTTPHeaderField: "Origin")
        request.setValue("https://platform.deepseek.com/usage", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekUsageError.invalidResponse(nil)
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw DeepSeekUsageError.unauthorized
        }

        guard http.statusCode == 200 else {
            throw DeepSeekUsageError.invalidResponse("DeepSeek API returned HTTP \(http.statusCode)")
        }

        return data
    }

    private func decodeEnvelope<T: Decodable>(_ data: Data) throws -> T {
        let envelope: DeepSeekAPIEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(DeepSeekAPIEnvelope<T>.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw DeepSeekUsageError.invalidResponse("DeepSeek decode failed: \(error.localizedDescription). Body: \(body.prefix(500))")
        }
        guard envelope.apiCode == 0 else {
            throw DeepSeekUsageError.invalidResponse("DeepSeek API returned code \(envelope.apiCode)")
        }
        guard envelope.bizCode == 0 else {
            throw DeepSeekUsageError.invalidResponse("DeepSeek API biz_code = \(envelope.bizCode)")
        }
        guard let bizData = envelope.bizData else {
            throw DeepSeekUsageError.invalidResponse("DeepSeek API returned null biz_data")
        }
        return bizData
    }

    // MARK: - Snapshot assembly

    private func makeSnapshot(
        summary: DeepSeekSummaryResponse,
        usage: DeepSeekUsageResponse,
        cost: DeepSeekCostResponse,
        today: String
    ) -> DeepSeekUsageSnapshot {
        let balance = Double(summary.walletBalance ?? "0") ?? 0

        let todayTokens = Self.extractTodayTokens(from: usage, today: today)
        let todayCost = Self.extractTodayCost(from: cost, today: today)
        let monthlyTokens = Int(summary.monthlyTokenUsage ?? "0") ?? 0
        let monthlyCost = Double(summary.monthlyCosts?.first?.amount ?? "0") ?? 0

        return DeepSeekUsageSnapshot(
            refreshedAt: Date(),
            balance: balance,
            todayPromptTokens: todayTokens.prompt,
            todayCompletionTokens: todayTokens.completion,
            todayCacheHitTokens: todayTokens.cacheHit,
            todayCacheMissTokens: todayTokens.cacheMiss,
            todayCost: todayCost,
            monthlyTokens: monthlyTokens,
            monthlyCost: monthlyCost
        )
    }

    // MARK: - Helpers

    private static func extractTodayTokens(from usage: DeepSeekUsageResponse, today: String) -> (prompt: Int, completion: Int, cacheHit: Int, cacheMiss: Int) {
        guard let todayEntry = usage.days?.first(where: { $0.date == today }) else {
            return (0, 0, 0, 0)
        }

        var prompt = 0, completion = 0, cacheHit = 0, cacheMiss = 0

        for modelEntry in todayEntry.data ?? [] {
            for ut in modelEntry.usage ?? [] {
                let amount = Int(ut.amount ?? "0") ?? 0
                switch ut.type {
                case "PROMPT_TOKEN":
                    prompt += amount
                case "PROMPT_CACHE_HIT_TOKEN":
                    prompt += amount
                    cacheHit += amount
                case "PROMPT_CACHE_MISS_TOKEN":
                    prompt += amount
                    cacheMiss += amount
                case "RESPONSE_TOKEN":
                    completion += amount
                default:
                    break
                }
            }
        }

        return (prompt, completion, cacheHit, cacheMiss)
    }

    private static func extractTodayCost(from cost: DeepSeekCostResponse, today: String) -> Double {
        guard let todayEntry = cost.days?.first(where: { $0.date == today }) else {
            return 0
        }

        var total = 0.0
        for modelEntry in todayEntry.data ?? [] {
            for ut in modelEntry.usage ?? [] {
                total += Double(ut.amount ?? "0") ?? 0
            }
        }
        return total
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func todayComponents() -> (month: Int, year: Int) {
        let cal = Calendar.current
        let now = Date()
        return (cal.component(.month, from: now), cal.component(.year, from: now))
    }
}
