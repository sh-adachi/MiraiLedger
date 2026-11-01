import Foundation

public enum ProjectionScenario: String, CaseIterable, Identifiable, Sendable {
    case conservative, base, optimistic
    public var id: String { rawValue }
    public var title: String {
        switch self { case .conservative: "慎重"; case .base: "標準"; case .optimistic: "積極" }
    }
    public var annualReturnAdjustment: Double {
        switch self { case .conservative: -2; case .base: 0; case .optimistic: 2 }
    }
}

public struct ProjectionPoint: Identifiable, Equatable, Sendable {
    public var id: Int { month }
    public let month: Int
    public let date: Date
    public let cashBalance: Double
    public let investmentBalance: Double
    public let debt: Double
    public let realNetWorth: Double
    /// Net external cashflow since the starting snapshot. Expenses reduce this figure.
    public let cumulativeContributions: Double
    public let cumulativeGrowth: Double
    public let cumulativeNISAOverflow: Double
    public let assetValues: [UUID: Double]
    public var totalAssets: Double { cashBalance + investmentBalance }
    public var netWorth: Double { totalAssets - debt }
}

public struct ProjectionResult: Sendable {
    public let points: [ProjectionPoint]
    public let goalReachedMonth: Int?
    public let initialAssets: Double
    public let monthlySurplus: Double
    public let scenario: ProjectionScenario
    /// The engine always produces the initial point and at least one monthly point.
    public var finalPoint: ProjectionPoint { points[points.count - 1] }
    public var firstDebtMonth: Int? { points.first { $0.debt > 0.005 }?.month }
}

/// Deterministic, pre-tax market-value projection. No security selection, tax savings,
/// capital-gains tax, fees or interest on a cash shortfall are inferred. Cash earns 0%.
/// Effective annual returns convert to monthly rates; market growth is applied first,
/// then the month's net recurring/event cashflow is applied at month end.
///
/// NISA: annual purchase caps are 1.2m / 2.4m yen, total book-value cap 18m,
/// growth book-value cap 12m. A sale restores its book-value capacity the next year.
/// The model assumes the entered holdings are eligible for their selected NISA slot.
/// https://www.fsa.go.jp/policy/nisa2/know/index.html
public enum ProjectionEngine {
    public static var calendar: Calendar { FinanceCalendar.value }
    public static func project(state: HouseholdState, scenario: ProjectionScenario = .base,
                               calendar: Calendar = FinanceCalendar.value) throws -> ProjectionResult {
        try state.validate()
        let investments = state.assets.filter { $0.kind != .cash }
        let cashAccounts = state.assets.filter { $0.kind == .cash }
        var values = Dictionary(uniqueKeysWithValues: investments.map { ($0.id, $0.balance) })
        var bookValues = Dictionary(uniqueKeysWithValues: investments.map { ($0.id, $0.costBasis) })
        var cash = state.cashBalance
        var debt = 0.0
        var netContributions = 0.0
        var totalGrowth = 0.0
        var nisaOverflow = 0.0
        var year = calendar.component(.year, from: state.plan.startDate)
        var tsumitateUsed = state.nisaUsage.calendarYear == year ? state.nisaUsage.tsumitateAnnualUsed : 0
        var growthUsed = state.nisaUsage.calendarYear == year ? state.nisaUsage.growthAnnualUsed : 0
        var occupiedNISA = investments.filter { $0.taxTreatment.isNISA }.reduce(0) { $0 + $1.costBasis }
        var occupiedGrowth = investments.filter { $0.taxTreatment == .nisaGrowth }.reduce(0) { $0 + $1.costBasis }
        var releasedNextYear = 0.0
        var growthReleasedNextYear = 0.0
        let totalWeight = investments.reduce(0) { $0 + $1.contributionWeight }
        let monthlyMultipliers = Dictionary(uniqueKeysWithValues: investments.map { asset in
            // A pessimistic scenario never assumes a loss beyond the entire holding.
            let annual = max(-100, asset.annualReturnPercent + scenario.annualReturnAdjustment)
            return (asset.id, pow(1 + annual / 100, 1.0 / 12.0))
        })
        let eventsByMonth = Dictionary(grouping: state.events, by: \.month)
        var points: [ProjectionPoint] = []
        points.reserveCapacity(state.plan.months + 1)

        func point(month: Int, date: Date) -> ProjectionPoint {
            let investmentBalance = values.values.reduce(0, +)
            var perAsset = values
            // Cashflow is pooled. Distribute the pool proportionally for the optional
            // per-asset view; this has no effect on projection calculations.
            for (index, account) in cashAccounts.enumerated() {
                perAsset[account.id] = state.cashBalance > 0 ? cash * account.balance / state.cashBalance : (index == 0 ? cash : 0)
            }
            return ProjectionPoint(month: month, date: date, cashBalance: cash, investmentBalance: investmentBalance,
                                   debt: debt, realNetWorth: (cash + investmentBalance - debt) / pow(1 + state.plan.annualInflationPercent / 100, Double(month) / 12),
                                   cumulativeContributions: netContributions, cumulativeGrowth: totalGrowth,
                                   cumulativeNISAOverflow: nisaOverflow, assetValues: perAsset)
        }
        points.append(point(month: 0, date: state.plan.startDate))

        for month in 1...state.plan.months {
            guard let date = calendar.date(byAdding: .month, value: month, to: state.plan.startDate) else {
                throw ValidationError.invalid("試算の日付を計算できません。")
            }
            let nextYear = calendar.component(.year, from: date)
            if nextYear != year {
                tsumitateUsed = 0; growthUsed = 0
                occupiedNISA = max(0, occupiedNISA - releasedNextYear)
                occupiedGrowth = max(0, occupiedGrowth - growthReleasedNextYear)
                releasedNextYear = 0; growthReleasedNextYear = 0; year = nextYear
            }
            for asset in investments {
                let before = values[asset.id, default: 0]
                let after = before * monthlyMultipliers[asset.id, default: 1]
                values[asset.id] = after; totalGrowth += after - before
            }
            let eventFlow = (eventsByMonth[month] ?? []).reduce(0.0) { sum, event in
                sum + (event.kind == .income ? event.amount : -event.amount)
            }
            let cashflow = state.monthlySurplus + eventFlow
            netContributions += cashflow
            if cashflow < 0 {
                var needed = -cashflow
                let cashWithdrawal = min(cash, needed)
                cash -= cashWithdrawal; needed -= cashWithdrawal
                let invested = values.values.reduce(0, +)
                let sale = min(invested, needed)
                if sale > 0 && invested > 0 {
                    let fraction = min(1, sale / invested)
                    for asset in investments {
                        values[asset.id, default: 0] *= 1 - fraction
                        let soldBasis = bookValues[asset.id, default: 0] * fraction
                        bookValues[asset.id, default: 0] -= soldBasis
                        if asset.taxTreatment.isNISA { releasedNextYear += soldBasis }
                        if asset.taxTreatment == .nisaGrowth { growthReleasedNextYear += soldBasis }
                    }
                }
                needed -= sale
                debt += max(0, needed)
            } else {
                let repayment = min(cashflow, debt)
                debt -= repayment
                let available = cashflow - repayment
                let intendedInvestment = totalWeight > 0 ? available * state.plan.investmentRatioPercent / 100 : 0
                var requests = Dictionary(uniqueKeysWithValues: investments.map { asset in
                    (asset.id, totalWeight > 0 ? intendedInvestment * asset.contributionWeight / totalWeight : 0)
                })
                let tsumitateRequest = investments.filter { $0.taxTreatment == .nisaTsumitate }.reduce(0) { $0 + requests[$1.id, default: 0] }
                let growthRequest = investments.filter { $0.taxTreatment == .nisaGrowth }.reduce(0) { $0 + requests[$1.id, default: 0] }
                let tsumitateFactor = tsumitateRequest > 0 ? min(1, max(0, 1_200_000 - tsumitateUsed) / tsumitateRequest) : 1
                let growthCapacity = max(0, min(2_400_000 - growthUsed, 12_000_000 - occupiedGrowth))
                let growthFactor = growthRequest > 0 ? min(1, growthCapacity / growthRequest) : 1
                for asset in investments {
                    if asset.taxTreatment == .nisaTsumitate { requests[asset.id, default: 0] *= tsumitateFactor }
                    if asset.taxTreatment == .nisaGrowth { requests[asset.id, default: 0] *= growthFactor }
                }
                let nisaRequest = investments.filter { $0.taxTreatment.isNISA }.reduce(0) { $0 + requests[$1.id, default: 0] }
                let nisaFactor = nisaRequest > 0 ? min(1, max(0, 18_000_000 - occupiedNISA) / nisaRequest) : 1
                var investedThisMonth = 0.0
                for asset in investments {
                    let accepted = requests[asset.id, default: 0] * (asset.taxTreatment.isNISA ? nisaFactor : 1)
                    values[asset.id, default: 0] += accepted
                    bookValues[asset.id, default: 0] += accepted
                    investedThisMonth += accepted
                    if asset.taxTreatment.isNISA { occupiedNISA += accepted }
                    if asset.taxTreatment == .nisaTsumitate { tsumitateUsed += accepted }
                    if asset.taxTreatment == .nisaGrowth { growthUsed += accepted; occupiedGrowth += accepted }
                }
                nisaOverflow += max(0, intendedInvestment - investedThisMonth)
                cash += max(0, available - investedThisMonth)
            }
            let next = point(month: month, date: date)
            guard next.netWorth.isFinite && next.realNetWorth.isFinite else { throw ValidationError.invalid("試算結果が計算できる範囲を超えました。") }
            points.append(next)
        }
        let goalMonth = state.plan.goalAmount > 0 ? points.first { $0.netWorth >= state.plan.goalAmount }?.month : nil
        return ProjectionResult(points: points, goalReachedMonth: goalMonth, initialAssets: state.totalAssets,
                                monthlySurplus: state.monthlySurplus, scenario: scenario)
    }
}
