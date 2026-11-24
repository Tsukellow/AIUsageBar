import Foundation

struct DeepSeekBalanceSettings: Equatable {
    static let balancePresets: [Double] = [5, 10, 20, 30, 50, 100, 200, 500, 1000]
    static let warningPresets: [Double] = [1, 2, 3, 4, 5, 10, 20]
    static let defaultFullBalance = 50.0
    static let defaultWarningPercent = 10.0

    let fullBalance: Double
    let warningPercent: Double

    init(fullBalance: Double, warningPercent: Double) {
        self.fullBalance = fullBalance.isFinite && fullBalance > 0
            ? fullBalance : Self.defaultFullBalance
        self.warningPercent = warningPercent.isFinite && warningPercent > 0 && warningPercent <= 100
            ? warningPercent : Self.defaultWarningPercent
    }

    var warningAmount: Double {
        self.fullBalance * self.warningPercent / 100
    }

    func ringFraction(for balance: Double) -> Double {
        guard balance.isFinite else { return 0 }
        return min(max(balance / self.fullBalance, 0), 1)
    }

    func isLowBalance(_ balance: Double) -> Bool {
        balance <= self.warningAmount
    }
}

/// A slider position represents an option, rather than a linear amount.
struct PresetValueScale {
    let values: [Double]

    init(presets: [Double], currentValue: Double) {
        var values = presets
        if currentValue.isFinite, currentValue > 0, !values.contains(currentValue) {
            values.append(currentValue)
        }
        self.values = values.sorted()
    }

    func index(for value: Double) -> Double {
        Double(self.values.firstIndex(of: value) ?? 0)
    }

    func value(at position: Double) -> Double {
        guard position.isFinite else { return self.values[0] }
        let index = Int(min(max(position.rounded(), 0), Double(self.values.count - 1)))
        return self.values[index]
    }
}
