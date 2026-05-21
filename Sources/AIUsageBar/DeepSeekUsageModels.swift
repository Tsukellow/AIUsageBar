import Foundation

struct DeepSeekUsageSnapshot: Sendable {
    let refreshedAt: Date
    let balance: Double
    let todayPromptTokens: Int
    let todayCompletionTokens: Int
    let todayCacheHitTokens: Int
    let todayCacheMissTokens: Int
    let todayCost: Double
    let monthlyTokens: Int
    let monthlyCost: Double

    var todayTotalTokens: Int {
        todayPromptTokens + todayCompletionTokens
    }

    var cacheHitRate: Double {
        let total = todayCacheHitTokens + todayCacheMissTokens
        guard total > 0 else { return 0 }
        return Double(todayCacheHitTokens) / Double(total) * 100
    }
}

enum DeepSeekUsageError: LocalizedError {
    case noToken
    case unauthorized
    case invalidResponse(String?)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No DeepSeek Bearer token configured. Paste your token in Settings."
        case .unauthorized:
            return "DeepSeek token invalid or expired. Copy a fresh token from platform.deepseek.com."
        case .invalidResponse(let detail):
            return detail ?? "Invalid response from DeepSeek API."
        }
    }
}

// MARK: - JSON response types

struct DeepSeekSummaryResponse: Decodable {
    let walletBalance: String?
    let bonusBalance: String?
    let monthlyTokenUsage: String?
    let monthlyCosts: [CostEntry]?

    struct CostEntry: Decodable {
        let amount: String?
    }

    struct Wallet: Decodable {
        let balance: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wallets = try container.decodeIfPresent([Wallet].self, forKey: .normalWallets)
        self.walletBalance = wallets?.first?.balance
        let bonus = try container.decodeIfPresent([Wallet].self, forKey: .bonusWallets)
        self.bonusBalance = bonus?.first?.balance
        self.monthlyTokenUsage = try container.decodeIfPresent(String.self, forKey: .monthlyTokenUsage)
        self.monthlyCosts = try container.decodeIfPresent([CostEntry].self, forKey: .monthlyCosts)
    }

    private enum CodingKeys: String, CodingKey {
        case normalWallets = "normal_wallets"
        case bonusWallets = "bonus_wallets"
        case monthlyTokenUsage = "monthly_token_usage"
        case monthlyCosts = "monthly_costs"
    }
}

struct DeepSeekUsageResponse: Decodable {
    let days: [DayEntry]?

    struct DayEntry: Decodable {
        let date: String?
        let data: [ModelEntry]?
    }

    struct ModelEntry: Decodable {
        let usage: [UsageEntry]?
    }

    struct UsageEntry: Decodable {
        let type: String?
        let amount: String?
    }
}

struct DeepSeekCostResponse: Decodable {
    let days: [DayEntry]?

    /// The cost endpoint returns biz_data as either `{days:[...]}` or `[{days:[...]}]`.
    init(from decoder: Decoder) throws {
        // Try single object first
        if let container = try? decoder.singleValueContainer(),
           let obj = try? container.decode(Inner.self) {
            self.days = obj.days
            return
        }
        // Try array, take first element
        if let container = try? decoder.singleValueContainer(),
           let arr = try? container.decode([Inner].self),
           let first = arr.first {
            self.days = first.days
            return
        }
        self.days = nil
    }

    private struct Inner: Decodable {
        let days: [DayEntry]?
    }

    struct DayEntry: Decodable {
        let date: String?
        let data: [ModelEntry]?
    }

    struct ModelEntry: Decodable {
        let usage: [UsageEntry]?
    }

    struct UsageEntry: Decodable {
        let amount: String?
    }
}

/// Outer wrapper: { code: 0, data: { biz_code: 0, biz_data: {...} } }
struct DeepSeekAPIEnvelope<BizData: Decodable>: Decodable {
    let apiCode: Int
    let bizCode: Int
    let bizData: BizData?

    private struct DataWrapper: Decodable {
        let bizCode: Int?
        let bizData: BizData?

        private enum CodingKeys: String, CodingKey {
            case bizCode = "biz_code"
            case bizData = "biz_data"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.apiCode = try container.decodeIfPresent(Int.self, forKey: .code) ?? -1
        let dataWrapper = try container.decodeIfPresent(DataWrapper.self, forKey: .data)
        self.bizCode = dataWrapper?.bizCode ?? -1
        self.bizData = dataWrapper?.bizData
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case data
    }
}
