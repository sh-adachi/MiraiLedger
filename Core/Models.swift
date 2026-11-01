import Foundation

/// Financial periods use Japan's Gregorian calendar regardless of device locale.
public enum FinanceCalendar {
    public static var value: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
}

public enum AssetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash, stock, fund, other
    public var id: String { rawValue }
    public var title: String {
        switch self { case .cash: "現金・預金"; case .stock: "株式"; case .fund: "投資信託"; case .other: "その他" }
    }
}

public enum TaxTreatment: String, Codable, CaseIterable, Identifiable, Sendable {
    case taxable, nisaTsumitate, nisaGrowth
    public var id: String { rawValue }
    public var title: String {
        switch self { case .taxable: "通常口座"; case .nisaTsumitate: "NISA つみたて投資枠"; case .nisaGrowth: "NISA 成長投資枠" }
    }
    public var isNISA: Bool { self != .taxable }
}

public enum EntryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case income, expense
    public var id: String { rawValue }
    public var title: String { self == .income ? "収入" : "支出" }
}

public struct Asset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AssetKind
    public var taxTreatment: TaxTreatment
    public var balance: Double
    public var costBasis: Double
    public var annualReturnPercent: Double
    public var contributionWeight: Double

    public init(id: UUID = UUID(), name: String, kind: AssetKind = .fund, taxTreatment: TaxTreatment = .taxable,
                balance: Double = 0, costBasis: Double = 0, annualReturnPercent: Double = 3, contributionWeight: Double = 1) {
        self.id = id; self.name = name; self.kind = kind; self.taxTreatment = taxTreatment
        self.balance = balance; self.costBasis = costBasis
        self.annualReturnPercent = annualReturnPercent; self.contributionWeight = contributionWeight
    }
}

public struct BudgetItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: String
    public var kind: EntryKind
    public var monthlyAmount: Double
    public init(id: UUID = UUID(), name: String, category: String, kind: EntryKind = .expense, monthlyAmount: Double = 0) {
        self.id = id; self.name = name; self.category = category; self.kind = kind; self.monthlyAmount = monthlyAmount
    }
}

/// Historical entries are a journal. Current asset balances are independent snapshots;
/// these entries never change the starting balances or the future recurring budget.
public struct LedgerTransaction: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: EntryKind
    public var category: String
    public var amount: Double
    public var note: String
    public init(id: UUID = UUID(), date: Date = Date(), kind: EntryKind = .expense, category: String, amount: Double, note: String = "") {
        self.id = id; self.date = date; self.kind = kind; self.category = category; self.amount = amount; self.note = note
    }
}

public struct PlannedEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var month: Int
    public var kind: EntryKind
    public var amount: Double
    public init(id: UUID = UUID(), name: String, month: Int, kind: EntryKind = .expense, amount: Double) {
        self.id = id; self.name = name; self.month = month; self.kind = kind; self.amount = amount
    }
}

public struct SimulationPlan: Codable, Equatable, Sendable {
    public var months: Int
    public var investmentRatioPercent: Double
    public var annualInflationPercent: Double
    public var goalAmount: Double
    public var startDate: Date
    public init(months: Int = 360, investmentRatioPercent: Double = 70, annualInflationPercent: Double = 2,
                goalAmount: Double = 30_000_000, startDate: Date = Date()) {
        self.months = months; self.investmentRatioPercent = investmentRatioPercent
        self.annualInflationPercent = annualInflationPercent; self.goalAmount = goalAmount; self.startDate = startDate
    }
}

public struct NISAUsage: Codable, Equatable, Sendable {
    public var calendarYear: Int
    public var tsumitateAnnualUsed: Double
    public var growthAnnualUsed: Double
    public init(calendarYear: Int = FinanceCalendar.value.component(.year, from: Date()),
                tsumitateAnnualUsed: Double = 0, growthAnnualUsed: Double = 0) {
        self.calendarYear = calendarYear; self.tsumitateAnnualUsed = tsumitateAnnualUsed; self.growthAnnualUsed = growthAnnualUsed
    }
}

/// Alternate assumptions applied to the current household, not a saved copy of balances.
public struct SimulationVariant: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var monthlyIncomeAdjustment: Double
    public var monthlyExpenseAdjustment: Double
    public var investmentRatioPercent: Double
    /// Percentage-point adjustment applied to noncash assets' effective annual returns.
    public var annualReturnAdjustment: Double

    public init(id: UUID = UUID(), name: String, monthlyIncomeAdjustment: Double = 0,
                monthlyExpenseAdjustment: Double = 0, investmentRatioPercent: Double = 70,
                annualReturnAdjustment: Double = 0) {
        self.id = id; self.name = name
        self.monthlyIncomeAdjustment = monthlyIncomeAdjustment; self.monthlyExpenseAdjustment = monthlyExpenseAdjustment
        self.investmentRatioPercent = investmentRatioPercent; self.annualReturnAdjustment = annualReturnAdjustment
    }

    /// Checks the saved assumptions themselves. Baseline-dependent checks are performed
    /// when applying the variant, so later budget edits cannot make household data unloadable.
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 else {
            throw ValidationError.invalid("比較プラン名を 200 文字以内で入力してください。")
        }
        for amount in [monthlyIncomeAdjustment, monthlyExpenseAdjustment] {
            guard amount.isFinite && abs(amount) <= 1_000_000_000_000_000 else {
                throw ValidationError.invalid("比較プランの収支調整額に有効な金額を入力してください。")
            }
        }
        guard investmentRatioPercent.isFinite && (0...100).contains(investmentRatioPercent) else {
            throw ValidationError.invalid("比較プランの投資割合は 0% から 100% で設定してください。")
        }
        guard annualReturnAdjustment.isFinite && (-20...20).contains(annualReturnAdjustment) else {
            throw ValidationError.invalid("比較プランの年利調整は -20 から +20 ポイントで設定してください。")
        }
    }
}

public struct HouseholdState: Codable, Equatable, Sendable {
    public var assets: [Asset]
    public var budgetItems: [BudgetItem]
    public var transactions: [LedgerTransaction]
    public var events: [PlannedEvent]
    public var variants: [SimulationVariant]
    public var plan: SimulationPlan
    public var nisaUsage: NISAUsage
    public var isSampleData: Bool
    public init(assets: [Asset] = [], budgetItems: [BudgetItem] = [], transactions: [LedgerTransaction] = [],
                events: [PlannedEvent] = [], variants: [SimulationVariant] = [], plan: SimulationPlan = .init(), nisaUsage: NISAUsage = .init(), isSampleData: Bool = false) {
        self.assets = assets; self.budgetItems = budgetItems; self.transactions = transactions
        self.events = events; self.variants = variants; self.plan = plan; self.nisaUsage = nisaUsage; self.isSampleData = isSampleData
    }

    private enum CodingKeys: String, CodingKey {
        case assets, budgetItems, transactions, events, variants, plan, nisaUsage, isSampleData
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        assets = try values.decode([Asset].self, forKey: .assets)
        budgetItems = try values.decode([BudgetItem].self, forKey: .budgetItems)
        transactions = try values.decode([LedgerTransaction].self, forKey: .transactions)
        events = try values.decode([PlannedEvent].self, forKey: .events)
        // Version 1 backups predate comparison plans. Missing alone means the old
        // format; malformed values (including null) must not silently discard plans.
        variants = values.contains(.variants) ? try values.decode([SimulationVariant].self, forKey: .variants) : []
        plan = try values.decode(SimulationPlan.self, forKey: .plan)
        nisaUsage = try values.decode(NISAUsage.self, forKey: .nisaUsage)
        isSampleData = try values.decode(Bool.self, forKey: .isSampleData)
    }
    public var monthlyIncome: Double { budgetItems.filter { $0.kind == .income }.reduce(0) { $0 + $1.monthlyAmount } }
    public var monthlyExpense: Double { budgetItems.filter { $0.kind == .expense }.reduce(0) { $0 + $1.monthlyAmount } }
    public var monthlySurplus: Double { monthlyIncome - monthlyExpense }
    public var totalAssets: Double { assets.reduce(0) { $0 + $1.balance } }
    public var cashBalance: Double { assets.filter { $0.kind == .cash }.reduce(0) { $0 + $1.balance } }
    public var investmentBalance: Double { totalAssets - cashBalance }
    public static var empty: HouseholdState { HouseholdState() }

    /// Entirely fictional figures for exploring the app, not investment recommendations.
    public static var sample: HouseholdState {
        let now = Date()
        let calendar = FinanceCalendar.value
        let currentMonth = calendar.dateInterval(of: .month, for: now)!.start
        var sampleTransactions = [
            LedgerTransaction(date: now, category: "食費", amount: 2_840, note: "サンプル：スーパー"),
            LedgerTransaction(date: max(currentMonth, now.addingTimeInterval(-86_400)), category: "娯楽", amount: 1_600, note: "サンプル：カフェ")
        ]
        for offset in 1...6 {
            let month = calendar.date(byAdding: .month, value: -offset, to: currentMonth)!
            sampleTransactions.append(contentsOf: [
                LedgerTransaction(date: calendar.date(byAdding: .day, value: 24, to: month)!, kind: .income, category: "給与", amount: 350_000, note: "サンプル：手取り給与"),
                LedgerTransaction(date: calendar.date(byAdding: .day, value: 19, to: month)!, category: "食費", amount: 42_000, note: "サンプル：1か月の食費"),
                LedgerTransaction(date: month, category: "住居", amount: 90_000, note: "サンプル：家賃"),
                LedgerTransaction(date: calendar.date(byAdding: .day, value: 11, to: month)!, category: "交通", amount: 10_000, note: "サンプル：1か月の交通費")
            ])
        }
        return HouseholdState(
            assets: [
                Asset(name: "生活用の預金", kind: .cash, balance: 1_800_000, annualReturnPercent: 0, contributionWeight: 0),
                Asset(name: "つみたて投資信託", kind: .fund, taxTreatment: .nisaTsumitate, balance: 2_200_000, costBasis: 1_900_000, annualReturnPercent: 4, contributionWeight: 70),
                Asset(name: "国内株式", kind: .stock, taxTreatment: .taxable, balance: 800_000, costBasis: 750_000, annualReturnPercent: 3, contributionWeight: 30)
            ],
            budgetItems: [
                BudgetItem(name: "手取り給与", category: "給与", kind: .income, monthlyAmount: 350_000),
                BudgetItem(name: "家賃", category: "住居", monthlyAmount: 90_000),
                BudgetItem(name: "食費", category: "食費", monthlyAmount: 45_000),
                BudgetItem(name: "水道・電気・ガス", category: "水道光熱費", monthlyAmount: 18_000),
                BudgetItem(name: "スマホ・インターネット", category: "通信", monthlyAmount: 9_000),
                BudgetItem(name: "日用品", category: "日用品", monthlyAmount: 12_000),
                BudgetItem(name: "おでかけ・趣味", category: "娯楽", monthlyAmount: 26_000),
                BudgetItem(name: "交通費", category: "交通", monthlyAmount: 10_000),
                BudgetItem(name: "保険", category: "保険", monthlyAmount: 10_000)
            ],
            transactions: sampleTransactions,
            events: [PlannedEvent(name: "旅行の予算", month: 12, amount: 200_000)],
            variants: [
                SimulationVariant(name: "月1万円の節約", monthlyExpenseAdjustment: -10_000),
                SimulationVariant(name: "収入を月3万円増やす", monthlyIncomeAdjustment: 30_000)
            ],
            plan: SimulationPlan(startDate: now), isSampleData: true
        )
    }
}

public enum ValidationError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

extension HouseholdState {
    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw ValidationError.invalid(message) } }
        func money(_ value: Double, _ title: String) throws {
            try require(value.isFinite && value >= 0 && value <= 1_000_000_000_000_000, "\(title)は 0 円以上の有効な金額を入力してください。")
        }
        func name(_ value: String, _ title: String) throws {
            try require(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 200, "\(title)を 200 文字以内で入力してください。")
        }
        func validDate(_ date: Date) -> Bool {
            let calendar = FinanceCalendar.value
            let lower = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
            let upper = calendar.date(from: DateComponents(year: 2201, month: 1, day: 1))!
            return date.timeIntervalSince1970.isFinite && date >= lower && date < upper
        }
        try require(assets.count <= 1_000 && budgetItems.count <= 1_000 && transactions.count <= 100_000 && events.count <= 1_000, "登録件数が上限を超えています。")
        try require(variants.count <= 20, "比較プランは 20 件まで保存できます。")
        try require(Set(assets.map(\.id)).count == assets.count && Set(budgetItems.map(\.id)).count == budgetItems.count
                    && Set(transactions.map(\.id)).count == transactions.count && Set(events.map(\.id)).count == events.count
                    && Set(variants.map(\.id)).count == variants.count, "重複したデータ ID があります。")
        for variant in variants { try variant.validate() }
        for asset in assets {
            try name(asset.name, "資産名"); try money(asset.balance, "資産残高"); try money(asset.costBasis, "取得額")
            try require(asset.annualReturnPercent.isFinite && (-99...100).contains(asset.annualReturnPercent), "年利は -99% から 100% の範囲で入力してください。")
            try require(asset.contributionWeight.isFinite && (0...1_000_000).contains(asset.contributionWeight), "積立の配分は 0 以上で入力してください。")
            try require(asset.kind != .cash || asset.taxTreatment == .taxable, "現金・預金に NISA 枠は指定できません。")
        }
        for item in budgetItems { try name(item.name, "項目名"); try name(item.category, "カテゴリ"); try money(item.monthlyAmount, "毎月の金額") }
        for transaction in transactions {
            try name(transaction.category, "カテゴリ"); try money(transaction.amount, "記録する金額")
            try require(transaction.note.count <= 2_000 && validDate(transaction.date), "記録の日付またはメモが無効です。")
        }
        for event in events {
            try name(event.name, "イベント名"); try money(event.amount, "イベントの金額")
            try require((1...600).contains(event.month), "イベントは 1 か月後から 600 か月後で設定してください。")
        }
        try require((1...600).contains(plan.months), "試算期間は 1 か月から 600 か月で設定してください。")
        try require(plan.investmentRatioPercent.isFinite && (0...100).contains(plan.investmentRatioPercent), "投資する割合は 0% から 100% で設定してください。")
        try require(plan.annualInflationPercent.isFinite && (-20...30).contains(plan.annualInflationPercent), "物価上昇率は -20% から 30% で設定してください。")
        try money(plan.goalAmount, "目標金額")
        try require(validDate(plan.startDate), "試算開始日が無効です。")
        try require((1900...2200).contains(nisaUsage.calendarYear), "NISA 利用額の対象年が無効です。")
        try money(nisaUsage.tsumitateAnnualUsed, "つみたて投資枠の年間利用額"); try money(nisaUsage.growthAnnualUsed, "成長投資枠の年間利用額")
        try require(nisaUsage.tsumitateAnnualUsed <= 1_200_000 && nisaUsage.growthAnnualUsed <= 2_400_000, "NISA の年間利用額が年間投資枠を超えています。")
        let nisaBasis = assets.filter { $0.taxTreatment.isNISA }.reduce(0) { $0 + $1.costBasis }
        let growthBasis = assets.filter { $0.taxTreatment == .nisaGrowth }.reduce(0) { $0 + $1.costBasis }
        try require(nisaBasis <= 18_000_000 && growthBasis <= 12_000_000, "NISA の取得額が非課税保有限度額を超えています。")
    }
}
