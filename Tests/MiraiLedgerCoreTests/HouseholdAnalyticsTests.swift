import XCTest
@testable import MiraiLedgerCore

final class HouseholdAnalyticsTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        FinanceCalendar.value.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testJSTMonthEdgesAndEmptyMonthsAreIncluded() {
        let start = date(2026, 10)
        let state = HouseholdState(transactions: [
            LedgerTransaction(date: start.addingTimeInterval(-1), category: "食費", amount: 2_000),
            LedgerTransaction(date: start, kind: .income, category: "給与", amount: 10_000),
            LedgerTransaction(date: date(2026, 11), category: "食費", amount: 500)
        ])
        let months = HouseholdAnalytics.months(in: state, ending: date(2026, 10, 15), count: 3)
        XCTAssertEqual(months.map(\.monthStart), [date(2026, 8), date(2026, 9), date(2026, 10)])
        XCTAssertEqual(months.map(\.income), [0, 0, 10_000])
        XCTAssertEqual(months.map(\.expense), [0, 2_000, 0])
        XCTAssertEqual(months.map(\.recordCount), [0, 1, 1])
        XCTAssertTrue(HouseholdAnalytics.months(in: state, ending: start, count: 0).isEmpty)
    }

    func testProposalAveragesOverAllSelectedMonthsIncludingUnrecordedMonths() throws {
        let state = HouseholdState(transactions: [
            LedgerTransaction(date: date(2026, 7, 8), category: "食費", amount: 9_000),
            LedgerTransaction(date: date(2026, 9, 20), category: "食費", amount: 3_000),
            LedgerTransaction(date: date(2026, 10), category: "食費", amount: 500_000)
        ])
        let proposal = try HouseholdAnalytics.budgetProposal(in: state, ending: date(2026, 9), monthCount: 3, referenceDate: date(2026, 10))
        XCTAssertEqual(proposal.periodStart, date(2026, 7))
        XCTAssertEqual(proposal.periodEndExclusive, date(2026, 10))
        XCTAssertEqual(proposal.recordedMonthCount, 2)
        XCTAssertEqual(proposal.recordCount, 2)
        XCTAssertEqual(proposal.items.first?.monthlyAmount, 4_000)
        XCTAssertTrue(proposal.canApply)
    }

    func testMergeReplacesMatchingDuplicatesAndPreservesUnrecordedCategories() throws {
        let rent = BudgetItem(name: "家賃", category: "住居", monthlyAmount: 90_000)
        let sameNameIncome = BudgetItem(name: "食費補助", category: "食費", kind: .income, monthlyAmount: 5_000)
        let state = HouseholdState(budgetItems: [
            BudgetItem(name: "自炊", category: "食費", monthlyAmount: 20_000),
            BudgetItem(name: "外食", category: "食費", monthlyAmount: 10_000), rent, sameNameIncome
        ], transactions: [LedgerTransaction(date: date(2026, 9, 5), category: "食費", amount: 25_000)])
        let before = state
        let proposal = try HouseholdAnalytics.budgetProposal(in: state, ending: date(2026, 9), monthCount: 1, referenceDate: date(2026, 10))
        let merged = proposal.mergedBudgetItems(current: state.budgetItems)
        XCTAssertEqual(merged.count, 3)
        XCTAssertTrue(merged.contains(rent))
        XCTAssertTrue(merged.contains(sameNameIncome))
        XCTAssertEqual(merged.first { $0.kind == .expense && $0.category == "食費" }?.monthlyAmount, 25_000)
        XCTAssertEqual(state, before, "Proposing never changes the journal or asset snapshot.")
    }

    func testEmptyPeriodDoesNotProduceDestructiveProposal() throws {
        let state = HouseholdState.sample
        let proposal = try HouseholdAnalytics.budgetProposal(in: state, ending: date(2000, 1), monthCount: 3, referenceDate: date(2026, 10))
        XCTAssertFalse(proposal.canApply)
        XCTAssertTrue(proposal.items.isEmpty)
        XCTAssertEqual(proposal.mergedBudgetItems(current: state.budgetItems), state.budgetItems)
    }

    func testIncompleteAndFutureMonthsRejected() {
        let today = date(2026, 10, 10)
        for month in [date(2026, 10), date(2026, 11)] {
            XCTAssertThrowsError(try HouseholdAnalytics.budgetProposal(in: .empty, ending: month, monthCount: 1, referenceDate: today))
        }
        for count in [0, 13] {
            XCTAssertThrowsError(try HouseholdAnalytics.budgetProposal(in: .empty, ending: date(2026, 9), monthCount: count, referenceDate: today))
        }
    }

    func testCategoryComparisonIncludesUnbudgetedAndBudgetOnlyCategories() {
        let state = HouseholdState(budgetItems: [
            BudgetItem(name: "食材", category: "食費", monthlyAmount: 20_000),
            BudgetItem(name: "外食", category: "食費", monthlyAmount: 10_000),
            BudgetItem(name: "家賃", category: "住居", monthlyAmount: 90_000)
        ], transactions: [
            LedgerTransaction(date: date(2026, 9, 10), category: "食費", amount: 35_000),
            LedgerTransaction(date: date(2026, 9, 11), category: "旅行", amount: 50_000),
            LedgerTransaction(date: date(2026, 9, 12), kind: .income, category: "食費", amount: 10_000)
        ])
        let categories = HouseholdAnalytics.categories(in: state, month: date(2026, 9), kind: .expense)
        XCTAssertEqual(categories.map(\.category), ["旅行", "食費", "住居"])
        XCTAssertEqual(categories.first { $0.category == "食費" }?.difference, 5_000)
        XCTAssertEqual(categories.first { $0.category == "住居" }?.actual, 0)
        XCTAssertEqual(categories.first { $0.category == "旅行" }?.hasBudget, false)
    }

    func testSampleProposalPreservesOtherBudgetsAndAssets() throws {
        let state = HouseholdState.sample
        let ending = FinanceCalendar.value.date(byAdding: .month, value: -1, to: state.plan.startDate)!
        let proposal = try HouseholdAnalytics.budgetProposal(in: state, ending: ending, monthCount: 1, referenceDate: state.plan.startDate)
        var updated = state
        updated.budgetItems = proposal.mergedBudgetItems(current: state.budgetItems)
        XCTAssertEqual(updated.monthlySurplus, 133_000)
        XCTAssertEqual(updated.assets, state.assets)
        XCTAssertEqual(updated.transactions, state.transactions)
        try updated.validate()
    }

    func testMaximumLengthCategoryCanBeAppliedWithoutTruncatingCategory() throws {
        let category = String(repeating: "家", count: 200)
        let state = HouseholdState(
            budgetItems: [BudgetItem(name: "現在の予算", category: category, monthlyAmount: 10_000)],
            transactions: [LedgerTransaction(date: date(2026, 9, 10), category: category, amount: 12_000)]
        )
        try state.validate()
        let proposal = try HouseholdAnalytics.budgetProposal(in: state, ending: date(2026, 9), monthCount: 1,
                                                            referenceDate: date(2026, 10))
        XCTAssertTrue(proposal.canApply)
        let proposed = try XCTUnwrap(proposal.items.first)
        XCTAssertEqual(proposed.name.count, 200)
        XCTAssertTrue(proposed.name.hasSuffix("（記録の平均）"))
        XCTAssertEqual(proposed.category, category)

        var updated = state
        updated.budgetItems = proposal.mergedBudgetItems(current: state.budgetItems)
        XCTAssertEqual(updated.budgetItems.count, 1)
        XCTAssertEqual(updated.budgetItems[0].category, category)
        XCTAssertEqual(updated.budgetItems[0].monthlyAmount, 12_000)
        try updated.validate()
    }
}
