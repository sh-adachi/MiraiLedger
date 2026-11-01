import Foundation

public struct MonthlyCashflow: Identifiable, Equatable, Sendable {
    public var id: Date { monthStart }
    public let monthStart: Date
    public let monthEndExclusive: Date
    public let income: Double
    public let expense: Double
    public let recordCount: Int
    public var surplus: Double { income - expense }
}

public struct CategoryBudgetComparison: Identifiable, Equatable, Sendable {
    public var id: String { kind.rawValue + "\u{1F}" + category }
    public let category: String
    public let kind: EntryKind
    public let actual: Double
    public let budget: Double
    public let hasBudget: Bool
    public var difference: Double { actual - budget }
}

/// A reviewable proposal derived only from complete journal months. Creating a
/// proposal has no side effects; applying it requires a separate store action.
public struct BudgetProposal: Equatable, Sendable {
    public let periodStart: Date
    public let periodEndExclusive: Date
    public let monthCount: Int
    public let recordedMonthCount: Int
    public let recordCount: Int
    public let items: [BudgetItem]
    public var canApply: Bool { recordCount > 0 && !items.isEmpty }

    /// Replace all budget rows matching a proposed (kind, category), including
    /// duplicate rows. Categories with no records remain exactly as they were.
    public func mergedBudgetItems(current: [BudgetItem]) -> [BudgetItem] {
        guard canApply else { return current }
        let proposedKeys = Set(items.map { BudgetCategoryKey(kind: $0.kind, category: $0.category) })
        return current.filter { !proposedKeys.contains(BudgetCategoryKey(kind: $0.kind, category: $0.category)) } + items
    }
}

private struct BudgetCategoryKey: Hashable {
    let kindValue: String
    let category: String
    var kind: EntryKind { EntryKind(rawValue: kindValue)! }
    init(kind: EntryKind, category: String) { self.kindValue = kind.rawValue; self.category = category }
}

public enum HouseholdAnalytics {
    /// Returns chronological buckets including the month containing `ending`.
    /// Empty months are present and their totals are zero. Boundaries are JST.
    public static func months(in state: HouseholdState, ending: Date, count: Int) -> [MonthlyCashflow] {
        let calendar = FinanceCalendar.value
        guard (1...120).contains(count), ending.timeIntervalSince1970.isFinite,
              let finalMonth = calendar.dateInterval(of: .month, for: ending),
              let firstMonth = calendar.date(byAdding: .month, value: -(count - 1), to: finalMonth.start) else { return [] }
        var incomes: [Date: Double] = [:]
        var expenses: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for entry in state.transactions where entry.date >= firstMonth && entry.date < finalMonth.end {
            guard let start = calendar.dateInterval(of: .month, for: entry.date)?.start else { continue }
            if entry.kind == .income { incomes[start, default: 0] += entry.amount }
            else { expenses[start, default: 0] += entry.amount }
            counts[start, default: 0] += 1
        }
        return (0..<count).compactMap { offset in
            guard let start = calendar.date(byAdding: .month, value: offset, to: firstMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return MonthlyCashflow(monthStart: start, monthEndExclusive: end, income: incomes[start, default: 0],
                                   expense: expenses[start, default: 0], recordCount: counts[start, default: 0])
        }
    }

    /// Current recurring budget versus the journal in one calendar month.
    /// Returns the union of journal and budget categories, including budget-only
    /// categories, and distinguishes income from expense with the same name.
    public static func categories(in state: HouseholdState, month: Date, kind: EntryKind) -> [CategoryBudgetComparison] {
        guard month.timeIntervalSince1970.isFinite,
              let interval = FinanceCalendar.value.dateInterval(of: .month, for: month) else { return [] }
        var actual: [String: Double] = [:]
        var budget: [String: Double] = [:]
        for item in state.budgetItems where item.kind == kind { budget[item.category, default: 0] += item.monthlyAmount }
        for entry in state.transactions where entry.kind == kind && entry.date >= interval.start && entry.date < interval.end {
            actual[entry.category, default: 0] += entry.amount
        }
        return Set(actual.keys).union(budget.keys).map { category in
            CategoryBudgetComparison(category: category, kind: kind, actual: actual[category, default: 0],
                                     budget: budget[category, default: 0], hasBudget: budget[category] != nil)
        }.sorted { lhs, rhs in
            lhs.actual == rhs.actual ? lhs.category < rhs.category : lhs.actual > rhs.actual
        }
    }

    /// Average the complete `monthCount` calendar months through `ending`.
    /// An unrecorded month contributes zero to every category's average. The
    /// currently open month and future months are never eligible for a proposal.
    public static func budgetProposal(in state: HouseholdState, ending: Date, monthCount: Int,
                                      referenceDate: Date = Date()) throws -> BudgetProposal {
        guard (1...12).contains(monthCount) else {
            throw ValidationError.invalid("予算の集計期間は1〜12か月で指定してください。")
        }
        let calendar = FinanceCalendar.value
        guard ending.timeIntervalSince1970.isFinite, referenceDate.timeIntervalSince1970.isFinite,
              let endingInterval = calendar.dateInterval(of: .month, for: ending),
              let currentInterval = calendar.dateInterval(of: .month, for: referenceDate),
              let start = calendar.date(byAdding: .month, value: -(monthCount - 1), to: endingInterval.start) else {
            throw ValidationError.invalid("予算の集計期間を確認してください。")
        }
        guard endingInterval.end <= currentInterval.start else {
            throw ValidationError.invalid("予算の提案には、すでに終了した月を選んでください。")
        }
        try state.validate()
        let records = state.transactions.filter { $0.date >= start && $0.date < endingInterval.end }
        var totals: [BudgetCategoryKey: Double] = [:]
        var recordedMonths = Set<Date>()
        for record in records {
            let key = BudgetCategoryKey(kind: record.kind, category: record.category)
            totals[key, default: 0] += record.amount
            if let month = calendar.dateInterval(of: .month, for: record.date)?.start { recordedMonths.insert(month) }
        }
        let nameSuffix = "（記録の平均）"
        let items = totals.map { key, total in
            BudgetItem(name: String(key.category.prefix(200 - nameSuffix.count)) + nameSuffix,
                       category: key.category, kind: key.kind, monthlyAmount: total / Double(monthCount))
        }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .income }
            return lhs.category < rhs.category
        }
        return BudgetProposal(periodStart: start, periodEndExclusive: endingInterval.end, monthCount: monthCount,
                              recordedMonthCount: recordedMonths.count, recordCount: records.count, items: items)
    }
}
