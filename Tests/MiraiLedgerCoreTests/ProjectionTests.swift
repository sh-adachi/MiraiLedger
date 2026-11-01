import Foundation
import XCTest
@testable import MiraiLedgerCore

final class ProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ year: Int = 2026, _ month: Int = 1, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func state(assets: [Asset] = [], income: Double = 0, expense: Double = 0, months: Int = 12,
                       investmentRatio: Double = 100, start: Date? = nil, events: [PlannedEvent] = []) -> HouseholdState {
        HouseholdState(assets: assets, budgetItems: [
            BudgetItem(name: "収入", category: "給与", kind: .income, monthlyAmount: income),
            BudgetItem(name: "支出", category: "生活", monthlyAmount: expense)
        ], events: events, plan: SimulationPlan(months: months, investmentRatioPercent: investmentRatio,
                                              annualInflationPercent: 0, goalAmount: 0, startDate: start ?? date()),
                       nisaUsage: NISAUsage(calendarYear: 2026))
    }
    private func run(_ state: HouseholdState, scenario: ProjectionScenario = .base) throws -> ProjectionResult {
        try ProjectionEngine.project(state: state, scenario: scenario, calendar: calendar)
    }

    func testEffectiveAnnualReturnAndZeroMonthSnapshot() throws {
        let input = state(assets: [Asset(name: "投信", balance: 1_000_000, annualReturnPercent: 12)])
        let result = try run(input)
        XCTAssertEqual(result.points.count, 13)
        XCTAssertEqual(result.points[0].netWorth, 1_000_000)
        XCTAssertEqual(result.points[1].netWorth, 1_000_000 * pow(1.12, 1.0 / 12), accuracy: 0.0001)
        XCTAssertEqual(result.finalPoint.netWorth, 1_120_000, accuracy: 0.0001)
        XCTAssertEqual(result.finalPoint.cumulativeGrowth, 120_000, accuracy: 0.0001)
    }

    func testContributionsOccurAtMonthEndAndCashKeepsRemainder() throws {
        let input = state(assets: [Asset(name: "投信", annualReturnPercent: 12)], income: 100_000, expense: 20_000,
                          months: 2, investmentRatio: 75)
        let result = try run(input)
        XCTAssertEqual(result.points[1].investmentBalance, 60_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[1].cashBalance, 20_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[2].investmentBalance, 60_000 * pow(1.12, 1.0 / 12) + 60_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[2].cashBalance, 40_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[2].cumulativeContributions, 160_000, accuracy: 0.0001)
    }

    func testInvestmentWeightsAndNoEligibleAssetKeepCash() throws {
        let first = Asset(name: "A", annualReturnPercent: 0, contributionWeight: 3)
        let second = Asset(name: "B", annualReturnPercent: 0, contributionWeight: 1)
        let result = try run(state(assets: [first, second], income: 100_000, months: 1))
        XCTAssertEqual(result.finalPoint.assetValues[first.id], 75_000)
        XCTAssertEqual(result.finalPoint.assetValues[second.id], 25_000)
        let cashOnly = try run(state(income: 100_000, months: 1))
        XCTAssertEqual(cashOnly.finalPoint.cashBalance, 100_000)
        XCTAssertEqual(cashOnly.finalPoint.cumulativeNISAOverflow, 0)
    }

    func testWithdrawalsUseCashThenProportionalAssetsThenDebt() throws {
        let first = Asset(name: "A", balance: 90_000, annualReturnPercent: 0)
        let second = Asset(name: "B", balance: 30_000, annualReturnPercent: 0)
        let result = try run(state(assets: [Asset(name: "現金", kind: .cash, balance: 20_000), first, second], expense: 100_000, months: 3))
        XCTAssertEqual(result.points[1].cashBalance, 0)
        XCTAssertEqual(result.points[1].assetValues[first.id]!, 30_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[1].assetValues[second.id]!, 10_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[2].debt, 60_000, accuracy: 0.0001)
        XCTAssertEqual(result.points[3].netWorth, -160_000, accuracy: 0.0001)
        XCTAssertEqual(result.firstDebtMonth, 2)
        XCTAssertEqual(result.points[3].cumulativeGrowth, 0)
    }

    func testSurplusPaysDownDebtBeforeInvesting() throws {
        let input = state(assets: [Asset(name: "投信", annualReturnPercent: 5)], months: 3, events: [
            PlannedEvent(name: "支払い", month: 1, amount: 100_000),
            PlannedEvent(name: "入金", month: 2, kind: .income, amount: 50_000),
            PlannedEvent(name: "入金", month: 3, kind: .income, amount: 70_000)
        ])
        let result = try run(input)
        XCTAssertEqual(result.points[1].debt, 100_000)
        XCTAssertEqual(result.points[2].debt, 50_000)
        XCTAssertEqual(result.points[2].investmentBalance, 0)
        XCTAssertEqual(result.finalPoint.debt, 0)
        XCTAssertEqual(result.finalPoint.investmentBalance, 20_000)
    }

    func testHistoricalTransactionsDoNotDoubleCountCash() throws {
        var input = state(assets: [Asset(name: "現金", kind: .cash, balance: 100_000)], months: 1)
        input.transactions = [LedgerTransaction(date: date(), kind: .income, category: "給与", amount: 350_000),
                              LedgerTransaction(date: date(), category: "家賃", amount: 90_000)]
        XCTAssertEqual(try run(input).finalPoint.netWorth, 100_000)
    }

    func testNISAAnnualLimitOverflowAndCalendarReset() throws {
        let asset = Asset(name: "NISA", taxTreatment: .nisaTsumitate, annualReturnPercent: 0)
        var input = state(assets: [asset], income: 100_000, months: 2, start: date(2026, 11))
        input.nisaUsage.tsumitateAnnualUsed = 1_190_000
        let result = try run(input)
        XCTAssertEqual(result.points[1].investmentBalance, 10_000)
        XCTAssertEqual(result.points[1].cashBalance, 90_000)
        XCTAssertEqual(result.points[2].investmentBalance, 110_000)
        XCTAssertEqual(result.finalPoint.cumulativeNISAOverflow, 90_000)
    }

    func testNISATotalBookValueLimitSharedProportionally() throws {
        let first = Asset(name: "つみたて", taxTreatment: .nisaTsumitate, balance: 10_000_000,
                          costBasis: 8_900_000, annualReturnPercent: 0)
        let second = Asset(name: "成長", taxTreatment: .nisaGrowth, balance: 11_000_000,
                           costBasis: 9_000_000, annualReturnPercent: 0)
        let result = try run(state(assets: [first, second], income: 400_000, months: 1))
        XCTAssertEqual(result.finalPoint.assetValues[first.id]!, 10_050_000, accuracy: 0.0001)
        XCTAssertEqual(result.finalPoint.assetValues[second.id]!, 11_050_000, accuracy: 0.0001)
        XCTAssertEqual(result.finalPoint.cashBalance, 300_000, accuracy: 0.0001)
    }

    func testNISAGrowthLimitUsesBookValueNotMarketValue() throws {
        let asset = Asset(name: "成長", taxTreatment: .nisaGrowth, balance: 9_000_000,
                          costBasis: 12_000_000, annualReturnPercent: 0)
        let result = try run(state(assets: [asset], income: 100_000, months: 1))
        XCTAssertEqual(result.finalPoint.investmentBalance, 9_000_000)
        XCTAssertEqual(result.finalPoint.cashBalance, 100_000)
    }

    func testNISASaleRestoresCapacityFollowingYearOnly() throws {
        let asset = Asset(name: "つみたて", taxTreatment: .nisaTsumitate, balance: 18_000_000,
                          costBasis: 18_000_000, annualReturnPercent: 0)
        let events = [PlannedEvent(name: "支払い", month: 1, amount: 1_000_000),
                      PlannedEvent(name: "入金", month: 2, kind: .income, amount: 1_000_000)]
        let sameYear = try run(state(assets: [asset], months: 2, events: events))
        XCTAssertEqual(sameYear.finalPoint.investmentBalance, 17_000_000)
        XCTAssertEqual(sameYear.finalPoint.cashBalance, 1_000_000)
        let nextYear = try run(state(assets: [asset], months: 2, start: date(2026, 11), events: events))
        XCTAssertEqual(nextYear.finalPoint.investmentBalance, 18_000_000)
        XCTAssertEqual(nextYear.finalPoint.cashBalance, 0)
    }

    func testScenariosAffectInvestmentsAndNeverCompoundDebtOrCash() throws {
        let input = state(assets: [Asset(name: "投信", balance: 1_000_000, annualReturnPercent: 4),
                                   Asset(name: "預金", kind: .cash, balance: 100_000, annualReturnPercent: 10)])
        XCTAssertEqual(try run(input, scenario: .conservative).finalPoint.netWorth, 1_120_000, accuracy: 0.001)
        XCTAssertEqual(try run(input, scenario: .optimistic).finalPoint.netWorth, 1_160_000, accuracy: 0.001)
        let extreme = state(assets: [Asset(name: "投信", balance: 1_000, annualReturnPercent: -99)], expense: 1_000, months: 12)
        let negative = try run(extreme, scenario: .conservative)
        XCTAssertEqual(negative.finalPoint.debt, 12_000)
        XCTAssertEqual(negative.finalPoint.investmentBalance, 0)
    }

    func testInflationAndGoalTiming() throws {
        var input = state(assets: [Asset(name: "預金", kind: .cash, balance: 100_000)], income: 10_000)
        input.plan.annualInflationPercent = 2
        input.plan.goalAmount = 150_000
        let result = try run(input)
        XCTAssertEqual(result.goalReachedMonth, 5)
        XCTAssertEqual(result.finalPoint.realNetWorth, 220_000 / 1.02, accuracy: 0.0001)
        input.plan.goalAmount = 50_000
        XCTAssertEqual(try run(input).goalReachedMonth, 0)
        input.plan.goalAmount = 0
        XCTAssertNil(try run(input).goalReachedMonth)
    }

    func testMonthEndDatesAndEventsOutsideHorizon() throws {
        var input = state(months: 2, start: date(2026, 1, 31), events: [PlannedEvent(name: "将来", month: 3, amount: 500)])
        let result = try run(input)
        XCTAssertEqual(calendar.component(.day, from: result.points[1].date), 28)
        XCTAssertEqual(calendar.component(.day, from: result.points[2].date), 31)
        XCTAssertEqual(result.finalPoint.netWorth, 0)
        input.plan.months = 600
        XCTAssertEqual(try run(input).points.count, 601)
    }

    func testCashflowGrowthAccountingIdentityForEveryMonth() throws {
        let result = try run(.sample)
        for point in result.points {
            XCTAssertEqual(point.netWorth, result.initialAssets + point.cumulativeContributions + point.cumulativeGrowth, accuracy: 0.05)
            XCTAssertGreaterThanOrEqual(point.cashBalance, 0)
            XCTAssertGreaterThanOrEqual(point.investmentBalance, 0)
        }
    }

    func testInvalidValuesAndPeriodsAreRejected() throws {
        for amount in [-1.0, Double.nan, .infinity] {
            var input = state()
            input.assets = [Asset(name: "不正", balance: amount)]
            XCTAssertThrowsError(try run(input))
        }
        for months in [0, -1, 601] {
            XCTAssertThrowsError(try run(state(months: months)))
        }
        var input = state()
        input.plan.investmentRatioPercent = .nan
        XCTAssertThrowsError(try run(input))
        input = state(assets: [Asset(name: "NISA", taxTreatment: .nisaGrowth, costBasis: 12_000_001)])
        XCTAssertThrowsError(try run(input))
        input = state()
        input.nisaUsage.tsumitateAnnualUsed = 1_200_001
        XCTAssertThrowsError(try run(input))
    }

    func testDefaultCalendarResetsNISAAtJapanNewYear() throws {
        // Dec 31 16:00 UTC is Jan 1 in Japan; the initial annual usage already belongs to 2027.
        let start = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 16))!
        var input = state(assets: [Asset(name: "NISA", taxTreatment: .nisaTsumitate, annualReturnPercent: 0)],
                          income: 100_000, months: 1, start: start)
        input.nisaUsage = NISAUsage(calendarYear: 2027, tsumitateAnnualUsed: 1_200_000)
        let result = try ProjectionEngine.project(state: input)
        XCTAssertEqual(ProjectionEngine.calendar.timeZone.identifier, "Asia/Tokyo")
        XCTAssertEqual(result.finalPoint.investmentBalance, 0)
        XCTAssertEqual(result.finalPoint.cashBalance, 100_000)
    }

    func testMalformedExtremeDatesRejectedBeforeCalendarCalculation() {
        for timestamp in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, Double.infinity, Double.nan] {
            var input = state()
            input.plan.startDate = Date(timeIntervalSince1970: timestamp)
            XCTAssertThrowsError(try input.validate())
            input = state()
            input.transactions = [LedgerTransaction(date: Date(timeIntervalSince1970: timestamp), category: "食費", amount: 10)]
            XCTAssertThrowsError(try input.validate())
        }
    }
}
