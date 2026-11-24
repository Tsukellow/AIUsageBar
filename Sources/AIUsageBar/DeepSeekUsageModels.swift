import Foundation

struct DeepSeekUsageSnapshot: Sendable {
    let refreshedAt: Date
    let balance: Double?
    let cacheHitRate: Double
    let todayCost: Double?
    let monthlyTokens: Int
    let monthlyCost: Double?
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
    let total: [ModelEntry]?

    /// The cost endpoint returns biz_data as either an object or a one-element array.
    init(from decoder: Decoder) throws {
        // Try single object first
        if let container = try? decoder.singleValueContainer(),
           let obj = try? container.decode(Inner.self) {
            self.days = obj.days
            self.total = obj.total
            return
        }
        // Try array, take first element
        if let container = try? decoder.singleValueContainer(),
           let arr = try? container.decode([Inner].self),
           let first = arr.first {
            self.days = first.days
            self.total = first.total
            return
        }
        self.days = nil
        self.total = nil
    }

    private struct Inner: Decodable {
        let days: [DayEntry]?
        let total: [ModelEntry]?

        private enum CodingKeys: String, CodingKey { case days, total }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Each period can still be usable if the other collection changes shape.
            self.days = try? container.decode([DayEntry].self, forKey: .days)
            self.total = try? container.decode([ModelEntry].self, forKey: .total)
        }
    }

    struct DayEntry: Decodable {
        let date: String?
        let data: [ModelEntry]?
    }

    struct ModelEntry: Decodable {
        let usage: [UsageEntry]?
    }

    struct UsageEntry: Decodable {
        let amount: Double?

        private enum CodingKeys: String, CodingKey { case amount }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let numeric = try? container.decode(Double.self, forKey: .amount)
            let text = try? container.decode(String.self, forKey: .amount)
            let value = numeric ?? text.flatMap { Double($0) }
            self.amount = value.flatMap { $0.isFinite ? $0 : nil }
        }
    }

    func cost(on date: String) -> Double? {
        guard let entries = self.days?.first(where: { $0.date == date })?.data else { return nil }
        return Self.sumCost(entries)
    }

    var monthlyCost: Double? {
        if let total, let sum = Self.sumCost(total) { return sum }

        guard let days else { return nil }
        var entries: [ModelEntry] = []
        for day in days {
            guard let data = day.data else { return nil }
            entries.append(contentsOf: data)
        }
        return Self.sumCost(entries)
    }

    private static func sumCost(_ modelEntries: [ModelEntry]) -> Double? {
        var total = 0.0
        var hasAmount = false
        for model in modelEntries {
            guard let entries = model.usage else { return nil }
            for entry in entries {
                guard let amount = entry.amount else { return nil }
                hasAmount = true
                total += amount
            }
        }
        return hasAmount && total.isFinite ? total : nil
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
