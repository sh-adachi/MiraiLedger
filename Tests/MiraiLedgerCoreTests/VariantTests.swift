import Foundation
import XCTest
@testable import MiraiLedgerCore

final class VariantTests: XCTestCase {
    private var baseline: HouseholdState {
        HouseholdState(
            assets: [Asset(name: "預金", kind: .cash, balance: 300_000, annualReturnPercent: 0),
                     Asset(name: "投信", balance: 1_000_000, annualReturnPercent: 0)],
            budgetItems: [BudgetItem(name: "給与", category: "給与", kind: .income, monthlyAmount: 300_000),
                          BudgetItem(name: "家賃", category: "住居", monthlyAmount: 90_000),
                          BudgetItem(name: "食費", category: "食費", monthlyAmount: 40_000)],
            transactions: [LedgerTransaction(category: "食費", amount: 2_000)],
            events: [PlannedEvent(name: "旅行", month: 6, amount: 200_000)],
            plan: SimulationPlan(months: 12, investmentRatioPercent: 70, annualInflationPercent: 0, goalAmount: 2_000_000),
            nisaUsage: NISAUsage(tsumitateAnnualUsed: 400_000)
        )
    }

    func testExpenseReductionAddsTwelveMonthsOfSavingsWithoutMutatingBaseline() throws {
        var original = baseline
        let variant = SimulationVariant(name: "節約", monthlyExpenseAdjustment: -10_000)
        original.variants = [variant]
        let snapshot = original
        let alternate = try VariantCalculator.applying(variant, to: original)
        let baseResult = try ProjectionEngine.project(state: original)
        let alternateResult = try ProjectionEngine.project(state: alternate)
        XCTAssertEqual(alternateResult.finalPoint.netWorth - baseResult.finalPoint.netWorth, 120_000, accuracy: 0.001)
        XCTAssertEqual(original, snapshot)
        XCTAssertTrue(alternate.variants.isEmpty)
        XCTAssertEqual(alternate.assets, original.assets)
        XCTAssertEqual(alternate.events, original.events)
        XCTAssertEqual(alternate.transactions, original.transactions)
        XCTAssertEqual(alternate.nisaUsage, original.nisaUsage)
        XCTAssertEqual(alternate.plan, original.plan)
        XCTAssertTrue(alternate.budgetItems.allSatisfy { $0.monthlyAmount >= 0 })
    }

    func testIncomeAndExpenseAdjustmentsUseCurrentBudgetEveryTime() throws {
        let variant = SimulationVariant(name: "増収と支出増", monthlyIncomeAdjustment: 30_000, monthlyExpenseAdjustment: 10_000)
        let first = try VariantCalculator.applying(variant, to: baseline)
        XCTAssertEqual(first.monthlyIncome, 330_000)
        XCTAssertEqual(first.monthlyExpense, 140_000)
        var changed = baseline
        changed.budgetItems[0].monthlyAmount = 320_000
        let second = try VariantCalculator.applying(variant, to: changed)
        XCTAssertEqual(second.monthlyIncome, 350_000)
        XCTAssertEqual(second.monthlySurplus - first.monthlySurplus, 20_000)
    }

    func testIncomeAndExpenseCanReachZeroButCannotBecomeNegative() throws {
        let input = baseline
        let zero = SimulationVariant(name: "ゼロ", monthlyIncomeAdjustment: -input.monthlyIncome, monthlyExpenseAdjustment: -input.monthlyExpense)
        let alternate = try VariantCalculator.applying(zero, to: input)
        XCTAssertEqual(alternate.monthlyIncome, 0)
        XCTAssertEqual(alternate.monthlyExpense, 0)
        XCTAssertThrowsError(try VariantCalculator.applying(SimulationVariant(name: "過大", monthlyIncomeAdjustment: -input.monthlyIncome - 1), to: input))
        XCTAssertThrowsError(try VariantCalculator.applying(SimulationVariant(name: "過大", monthlyExpenseAdjustment: -input.monthlyExpense - 1), to: input))
        XCTAssertThrowsError(try VariantCalculator.applying(SimulationVariant(name: "支出なし", monthlyExpenseAdjustment: -1), to: .empty))
    }

    func testPositiveAdjustmentsWorkWithNoExistingBudgetItems() throws {
        let variant = SimulationVariant(name: "新生活", monthlyIncomeAdjustment: 200_000, monthlyExpenseAdjustment: 150_000)
        let alternate = try VariantCalculator.applying(variant, to: .empty)
        XCTAssertEqual(alternate.monthlyIncome, 200_000)
        XCTAssertEqual(alternate.monthlyExpense, 150_000)
        XCTAssertEqual(Set(alternate.budgetItems.map(\.id)).count, 2)
    }

    func testIncreasingBudgetReusesCapacityAtItemCountLimit() throws {
        var input = HouseholdState.empty
        input.budgetItems = (0..<1_000).map { index in BudgetItem(name: "項目\(index)", category: "生活", monthlyAmount: 100) }
        let alternate = try VariantCalculator.applying(SimulationVariant(name: "増額", monthlyExpenseAdjustment: 10_000), to: input)
        XCTAssertEqual(alternate.budgetItems.count, 1_000)
        XCTAssertEqual(alternate.monthlyExpense, 110_000)
    }

    func testReturnAdjustmentChangesInvestmentsOnlyAndUsesPercentagePoints() throws {
        var input = baseline
        input.budgetItems = []; input.events = []
        input.assets[1].annualReturnPercent = 4
        let alternate = try VariantCalculator.applying(SimulationVariant(name: "利回り", annualReturnAdjustment: 2), to: input)
        XCTAssertEqual(alternate.assets[0], input.assets[0])
        XCTAssertEqual(alternate.assets[1].annualReturnPercent, 6)
        XCTAssertEqual(alternate.assets[1].balance, input.assets[1].balance)
        XCTAssertEqual(try ProjectionEngine.project(state: alternate).finalPoint.netWorth, 1_360_000, accuracy: 0.001)
    }

    func testReturnRangeIsRejectedRatherThanClamped() {
        var input = baseline
        input.assets[1].annualReturnPercent = 99
        XCTAssertThrowsError(try VariantCalculator.applying(SimulationVariant(name: "超過", annualReturnAdjustment: 2), to: input))
        input.assets[1].annualReturnPercent = -99
        XCTAssertThrowsError(try VariantCalculator.applying(SimulationVariant(name: "超過", annualReturnAdjustment: -1), to: input))
    }

    func testInvestmentRatioAppliesWithoutChangingIncomeOrExpenses() throws {
        let alternate = try VariantCalculator.applying(SimulationVariant(name: "預金中心", investmentRatioPercent: 0), to: baseline)
        XCTAssertEqual(alternate.monthlySurplus, baseline.monthlySurplus)
        XCTAssertEqual(alternate.plan.investmentRatioPercent, 0)
        let point = try ProjectionEngine.project(state: alternate).points[1]
        XCTAssertEqual(point.cashBalance, 470_000)
        XCTAssertEqual(point.investmentBalance, 1_000_000)
    }

    func testInvalidVariantValuesNamesAndCountsAreRejected() throws {
        for amount in [Double.nan, .infinity, -.infinity, 1_000_000_000_000_001] {
            XCTAssertThrowsError(try SimulationVariant(name: "金額", monthlyIncomeAdjustment: amount).validate())
            XCTAssertThrowsError(try SimulationVariant(name: "金額", monthlyExpenseAdjustment: amount).validate())
        }
        for ratio in [-1.0, 101, Double.nan, .infinity] {
            XCTAssertThrowsError(try SimulationVariant(name: "割合", investmentRatioPercent: ratio).validate())
        }
        for adjustment in [-20.01, 20.01, Double.nan, .infinity] {
            XCTAssertThrowsError(try SimulationVariant(name: "年利", annualReturnAdjustment: adjustment).validate())
        }
        for name in ["", " \n ", String(repeating: "a", count: 201)] {
            XCTAssertThrowsError(try SimulationVariant(name: name).validate())
        }
        var input = baseline
        input.variants = (0..<21).map { SimulationVariant(name: "比較\($0)") }
        XCTAssertThrowsError(try input.validate())
        input.variants.removeLast()
        XCTAssertNoThrow(try input.validate())
        input.variants[1].id = input.variants[0].id
        XCTAssertThrowsError(try input.validate())
    }

    func testStaleAssumptionsDoNotBlockLoadingEditedHousehold() throws {
        var input = baseline
        input.variants = [SimulationVariant(name: "以前の節約案", monthlyExpenseAdjustment: -input.monthlyExpense)]
        input.budgetItems.removeAll { $0.kind == .expense }
        XCTAssertNoThrow(try input.validate())
        XCTAssertEqual(try LedgerRepository.decode(LedgerRepository.encode(input)), input)
        XCTAssertThrowsError(try VariantCalculator.applying(input.variants[0], to: input))
    }

    func testVersionTwoVariantRoundTrip() throws {
        var input = baseline
        input.variants = [SimulationVariant(name: "比較案", monthlyIncomeAdjustment: 10_000, monthlyExpenseAdjustment: -5_000,
                                           investmentRatioPercent: 50, annualReturnAdjustment: -1.5)]
        let data = try LedgerRepository.encode(input)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertEqual(try LedgerRepository.decode(data), input)
    }

    func testLegacyMissingVariantsLoadWithoutRewritingOriginalFile() throws {
        let input = baseline
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerRepository.encode(input)) as? [String: Any])
        var legacyState = try XCTUnwrap(envelope["state"] as? [String: Any])
        legacyState.removeValue(forKey: "variants")
        envelope["state"] = legacyState; envelope["schemaVersion"] = 1
        let legacyData = try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mirai-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try legacyData.write(to: url)
        let repository = LedgerRepository(url: url)
        XCTAssertEqual(try repository.load(), input)
        XCTAssertEqual(try Data(contentsOf: url), legacyData)
        let loaded = try XCTUnwrap(repository.load())
        try repository.save(loaded)
        let savedEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(savedEnvelope["schemaVersion"] as? Int, 2)
    }

    func testMalformedNewVariantsAndMissingLegacyRequiredFieldsAreRejected() throws {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: LedgerRepository.encode(baseline)) as? [String: Any])
        var malformed = try XCTUnwrap(envelope["state"] as? [String: Any])
        malformed["variants"] = NSNull()
        envelope["state"] = malformed
        XCTAssertThrowsError(try LedgerRepository.decode(JSONSerialization.data(withJSONObject: envelope)))
        malformed.removeValue(forKey: "variants")
        malformed.removeValue(forKey: "assets")
        envelope["state"] = malformed; envelope["schemaVersion"] = 1
        XCTAssertThrowsError(try LedgerRepository.decode(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testSampleHasSixCompletedMonthsAndDemonstrationVariants() throws {
        let input = HouseholdState.sample
        let calendar = FinanceCalendar.value
        let currentMonth = try XCTUnwrap(calendar.dateInterval(of: .month, for: input.plan.startDate)).start
        // The first two entries are the original recent samples; inspect the appended history.
        let completed = Array(input.transactions.dropFirst(2))
        XCTAssertEqual(completed.count, 24)
        XCTAssertTrue(completed.allSatisfy { $0.date < currentMonth })
        let months = Dictionary(grouping: completed) { calendar.dateInterval(of: .month, for: $0.date)!.start }
        XCTAssertEqual(months.count, 6)
        for entries in months.values {
            XCTAssertEqual(entries.count, 4)
            XCTAssertEqual(entries.first { $0.category == "給与" }?.amount, 350_000)
            XCTAssertEqual(entries.first { $0.category == "食費" }?.amount, 42_000)
            XCTAssertEqual(entries.first { $0.category == "住居" }?.amount, 90_000)
            XCTAssertEqual(entries.first { $0.category == "交通" }?.amount, 10_000)
        }
        XCTAssertEqual(input.variants.map(\.name), ["月1万円の節約", "収入を月3万円増やす"])
        XCTAssertTrue(input.isSampleData)
        XCTAssertEqual(input.monthlySurplus, 130_000)
        try input.validate()
    }
}
