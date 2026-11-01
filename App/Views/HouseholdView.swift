import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: HouseholdMode = .budget
    @State private var selectedMonth = Date()
    @State private var showingMonthPicker = false
    @State private var editingBudget: BudgetItem?
    @State private var editingTransaction: LedgerTransaction?
    @State private var deletingBudget: BudgetItem?
    @State private var deletingTransaction: LedgerTransaction?
    @State private var showingDeleteConfirmation = false
    @State private var operationError = ""
    @State private var showingOperationError = false

    private var monthlyTransactions: [LedgerTransaction] {
        store.data.transactions
            .filter { FinanceCalendar.value.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }
    private var actualIncome: Double {
        monthlyTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
    }
    private var actualExpense: Double {
        monthlyTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("家計簿の表示", selection: $mode) {
                        ForEach(HouseholdMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("householdMode")

                    if mode == .budget {
                        budgetSummary
                        budgetContent
                    } else {
                        monthSelector
                        actualSummary
                        transactionsContent
                    }
                    explanation
                }
                .padding(20)
            }
            .background(MTheme.background)
            .navigationTitle("家計簿")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { HouseholdInsightsView(month: selectedMonth) } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }.accessibilityLabel("家計レポート").accessibilityIdentifier("householdInsights")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addEntry) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(mode == .budget ? "予算を追加" : "記録を追加")
                    .accessibilityIdentifier(mode == .budget ? "addBudget" : "addTransaction")
                }
            }
            .sheet(item: $editingBudget) { item in
                BudgetEditor(item: item, isExisting: store.data.budgetItems.contains { $0.id == item.id })
            }
            .sheet(item: $editingTransaction) { item in
                TransactionEditor(item: item, isExisting: store.data.transactions.contains { $0.id == item.id })
            }
            .sheet(isPresented: $showingMonthPicker) {
                NavigationStack {
                    DatePicker("表示する月の日付", selection: $selectedMonth, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("表示する月を選択")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完了") { showingMonthPicker = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog("この項目を削除しますか？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let item = deletingBudget, !store.deleteBudget(item) { presentDeleteError() }
                    if let item = deletingTransaction, !store.deleteTransaction(item) { presentDeleteError() }
                    deletingBudget = nil
                    deletingTransaction = nil
                }
                Button("キャンセル", role: .cancel) {
                    deletingBudget = nil
                    deletingTransaction = nil
                }
            } message: {
                Text(deletingBudget != nil ? "毎月の予算から削除します。今後のシミュレーションにも反映されます。" : "この入出金の記録を削除します。資産の評価額は変わりません。")
            }
            .alert("削除できませんでした", isPresented: $showingOperationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(operationError)
            }
        }
        .tint(MTheme.teal)
    }

    private var budgetSummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.data.monthlySurplus >= 0 ? "未来へまわせるお金" : "毎月の収支不足")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(MTheme.lime)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Money.yen(store.data.monthlySurplus))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("monthlySurplus")
                Text("/ 月")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)
            HStack {
                summaryValue("毎月の収入", amount: store.data.monthlyIncome, isHero: true)
                Spacer()
                summaryValue("毎月の支出", amount: store.data.monthlyExpense, isHero: true, alignment: .trailing)
            }
            Text("余剰金のうち、設定した割合を毎月の積立へ。")
                .font(.caption)
                .foregroundStyle(MTheme.lime)
        }
        .padding(24)
        .background(MTheme.forest, in: RoundedRectangle(cornerRadius: 28))
    }

    private var budgetContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach([EntryKind.income, EntryKind.expense]) { kind in
                let entries = store.data.budgetItems.filter { $0.kind == kind }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            MSectionTitle(title: kind == .income ? "毎月の収入" : "毎月の支出")
                            Text(kind == .income ? "手取り額を登録しましょう。" : "暮らしに必要なお金を見える化。")
                                .font(.caption).foregroundStyle(MTheme.muted)
                        }
                        Spacer()
                        Button {
                            editingBudget = BudgetItem(name: "", category: EntryCategories.defaults(for: kind)[0], kind: kind)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(kind == .income ? "収入の予算を追加" : "支出の予算を追加")
                    }
                    if entries.isEmpty {
                        MCard {
                            Text(kind == .income ? "給与や副業など、毎月の収入を追加してください。" : "家賃や食費など、毎月の支出を追加してください。")
                                .font(.subheadline)
                                .foregroundStyle(MTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    } else {
                        MCard {
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().padding(.leading, 52) }
                                    budgetRow(item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func budgetRow(_ item: BudgetItem) -> some View {
        HStack(spacing: 12) {
            categoryIcon(item.category, kind: item.kind)
            Button { editingBudget = item } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(MTheme.ink)
                        Text(item.category).font(.caption).foregroundStyle(MTheme.muted)
                    }
                    Spacer(minLength: 4)
                    Text(Money.yen(item.monthlyAmount))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(MTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name)、\(Money.yen(item.monthlyAmount))、編集")
            Menu {
                Button("編集", systemImage: "pencil") { editingBudget = item }
                Button("削除", systemImage: "trash", role: .destructive) {
                    deletingTransaction = nil
                    deletingBudget = item
                    showingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(MTheme.muted)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.name)の操作")
        }
        .padding(.vertical, 12)
    }

    private var monthSelector: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("前の月")
            Spacer()
            Button { showingMonthPicker = true } label: {
                HStack(spacing: 8) {
                    Text(Money.date(selectedMonth, format: "yyyy年M月"))
                        .font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(MTheme.ink)
            }
            .accessibilityLabel("表示月を変更")
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("次の月")
        }
        .padding(.horizontal, 2)
        .background(MTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var actualSummary: some View {
        MCard {
            VStack(spacing: 18) {
                HStack {
                    summaryValue("記録した収入", amount: actualIncome)
                    Spacer()
                    summaryValue("記録した支出", amount: actualExpense, alignment: .trailing)
                }
                Divider()
                HStack {
                    Text("この月の収支").font(.subheadline).foregroundStyle(MTheme.muted)
                    Spacer()
                    Text(Money.yen(actualIncome - actualExpense))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(actualIncome - actualExpense < 0 ? MTheme.red : MTheme.teal)
                        .accessibilityIdentifier("actualMonthlyBalance")
                }
                if store.data.monthlyExpense > 0 {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("支出予算に対する記録額")
                            Spacer()
                            Text("\(Int(min(actualExpense / store.data.monthlyExpense * 100, 9999)))%")
                        }
                        .font(.caption)
                        .foregroundStyle(MTheme.muted)
                        ProgressView(value: min(actualExpense / store.data.monthlyExpense, 1))
                            .tint(actualExpense > store.data.monthlyExpense ? MTheme.gold : MTheme.teal)
                    }
                }
            }
        }
    }

    private var transactionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MSectionTitle(title: "入出金の記録", subtitle: "\(monthlyTransactions.count)件の記録")
                Spacer()
                if !FinanceCalendar.value.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) {
                    Button("今月へ") { selectedMonth = Date() }
                        .font(.caption.weight(.semibold))
                }
            }
            if monthlyTransactions.isEmpty {
                MCard {
                    VStack(spacing: 14) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 30))
                            .foregroundStyle(MTheme.teal)
                        Text("この月の記録はまだありません")
                            .font(.headline)
                        Text("今日のお買い物から、気軽に記録。")
                            .font(.subheadline)
                            .foregroundStyle(MTheme.muted)
                        Button("記録を追加", action: addEntry)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                MCard {
                    VStack(spacing: 0) {
                        ForEach(Array(monthlyTransactions.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 52) }
                            transactionRow(item)
                        }
                    }
                }
            }
        }
    }

    private func transactionRow(_ item: LedgerTransaction) -> some View {
        HStack(spacing: 12) {
            categoryIcon(item.category, kind: item.kind)
            Button { editingTransaction = item } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.note.isEmpty ? item.category : item.note)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MTheme.ink)
                            .lineLimit(2)
                        Text("\(Money.date(item.date, format: "MM/dd")) · \(item.category)")
                            .font(.caption)
                            .foregroundStyle(MTheme.muted)
                    }
                    Spacer(minLength: 2)
                    Text("\(item.kind == .income ? "+" : "−")\(Money.yen(item.amount))")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(item.kind == .income ? MTheme.teal : MTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button("編集", systemImage: "pencil") { editingTransaction = item }
                Button("削除", systemImage: "trash", role: .destructive) {
                    deletingBudget = nil
                    deletingTransaction = item
                    showingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(MTheme.muted)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.category)の記録を操作")
        }
        .padding(.vertical, 12)
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode == .budget ? "arrow.triangle.branch" : "info.circle")
                .font(.subheadline)
                .foregroundStyle(MTheme.teal)
            Text(mode == .budget
                 ? "毎月の予算は、これからの暮らしの想定です。収入から支出を引いた残額をもとに、将来の積立を計算します。"
                 : "日々の記録は、暮らしを振り返るための家計簿です。シミュレーションには「毎月の予算」を使います。記録を追加しても資産の評価額や予算は変わりません。")
                .font(.caption)
                .foregroundStyle(MTheme.muted)
                .lineSpacing(4)
        }
        .padding(.horizontal, 4)
    }

    private func summaryValue(_ title: String, amount: Double, isHero: Bool = false, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isHero ? .white.opacity(0.7) : MTheme.muted)
            Text(Money.yen(amount))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(isHero ? .white : MTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func categoryIcon(_ category: String, kind: EntryKind) -> some View {
        Image(systemName: EntryCategories.symbol(for: category, kind: kind))
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(kind == .income ? MTheme.teal : MTheme.ink.opacity(0.7))
            .frame(width: 40, height: 40)
            .background(MTheme.background, in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }

    private func presentDeleteError() {
        operationError = store.errorMessage ?? "削除できませんでした。もう一度お試しください。"
        store.errorMessage = nil
        showingOperationError = true
    }

    private func moveMonth(_ offset: Int) {
        if let month = FinanceCalendar.value.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = month
        }
    }

    private func addEntry() {
        if mode == .budget {
            editingBudget = BudgetItem(name: "", category: "食費")
        } else {
            let date = FinanceCalendar.value.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
                ? Date() : FinanceCalendar.value.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
            editingTransaction = LedgerTransaction(date: date, category: "食費", amount: 0)
        }
    }
}

private enum HouseholdMode: String, CaseIterable, Identifiable {
    case budget = "毎月の予算"
    case records = "日々の記録"
    var id: String { rawValue }
}

private enum EntryCategories {
    static func defaults(for kind: EntryKind) -> [String] {
        kind == .income
            ? ["給与", "副業", "賞与", "年金", "その他収入"]
            : ["食費", "住まい", "光熱費", "通信費", "日用品", "交通費", "医療・保険", "教育", "趣味・娯楽", "その他支出"]
    }

    static func choices(for kind: EntryKind, current: String) -> [String] {
        let values = defaults(for: kind)
        return values.contains(current) || current.isEmpty ? values : values + [current]
    }

    static func symbol(for category: String, kind: EntryKind) -> String {
        if kind == .income { return "arrow.down.left" }
        if category.contains("食") { return "fork.knife" }
        if category.contains("家") || category.contains("住") { return "house" }
        if category.contains("光熱") || category.contains("電気") { return "bolt" }
        if category.contains("通信") { return "wifi" }
        if category.contains("交通") { return "tram" }
        if category.contains("医療") || category.contains("保険") { return "heart" }
        if category.contains("教育") { return "book" }
        if category.contains("趣味") || category.contains("娯楽") { return "sparkles" }
        if category.contains("日用") { return "basket" }
        return "creditcard"
    }
}

private struct BudgetEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: BudgetItem
    let isExisting: Bool
    @State private var name: String
    @State private var category: String
    @State private var kind: EntryKind
    @State private var amount: String
    @State private var validationMessage = ""
    @State private var showingError = false

    init(item: BudgetItem, isExisting: Bool) {
        self.item = item
        self.isExisting = isExisting
        _name = State(initialValue: item.name)
        _category = State(initialValue: item.category)
        _kind = State(initialValue: item.kind)
        _amount = State(initialValue: Money.input(item.monthlyAmount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("収入・支出", selection: $kind) {
                        ForEach(EntryKind.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("budgetKind")
                    TextField("項目名（例：家賃）", text: $name)
                        .accessibilityIdentifier("budgetName")
                    Picker("カテゴリ", selection: $category) {
                        ForEach(EntryCategories.choices(for: kind, current: category), id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .accessibilityIdentifier("budgetCategory")
                    MoneyField(title: "毎月の金額", text: $amount, unit: "円", identifier: "budgetAmount")
                } header: {
                    Text("毎月の予算")
                } footer: {
                    Text(kind == .income ? "収入は税金や社会保険料を引いた手取り額で入力してください。賞与などは12か月で割った月平均を入力すると、長期の見通しに反映できます。" : "毎月の平均的な支出を入力してください。年払いの保険料などは12か月で割って入力できます。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MTheme.background)
            .navigationTitle(isExisting ? "予算を編集" : "予算を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveBudget")
                }
            }
            .onChange(of: kind) { _, newKind in
                category = EntryCategories.defaults(for: newKind)[0]
            }
            .alert("入力を確認してください", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
        .tint(MTheme.teal)
        .interactiveDismissDisabled()
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return fail("項目名を入力してください。") }
        guard let parsedAmount = Money.parse(amount), parsedAmount.isFinite, parsedAmount >= 0 else {
            return fail("毎月の金額は0以上の数値で入力してください。")
        }
        let updated = BudgetItem(id: item.id, name: trimmedName, category: category, kind: kind, monthlyAmount: parsedAmount)
        if store.saveBudget(updated) { dismiss() }
        else {
            let message = store.errorMessage ?? "保存できませんでした。もう一度お試しください。"
            store.errorMessage = nil
            fail(message)
        }
    }

    private func fail(_ message: String) {
        validationMessage = message
        showingError = true
    }
}

private struct TransactionEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: LedgerTransaction
    let isExisting: Bool
    @State private var date: Date
    @State private var kind: EntryKind
    @State private var category: String
    @State private var amount: String
    @State private var note: String
    @State private var validationMessage = ""
    @State private var showingError = false

    init(item: LedgerTransaction, isExisting: Bool) {
        self.item = item
        self.isExisting = isExisting
        _date = State(initialValue: item.date)
        _kind = State(initialValue: item.kind)
        _category = State(initialValue: item.category)
        _amount = State(initialValue: Money.input(item.amount))
        _note = State(initialValue: item.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("収入・支出", selection: $kind) {
                        ForEach(EntryKind.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("transactionKind")
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("transactionDate")
                    Picker("カテゴリ", selection: $category) {
                        ForEach(EntryCategories.choices(for: kind, current: category), id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .accessibilityIdentifier("transactionCategory")
                    MoneyField(title: "金額", text: $amount, unit: "円", identifier: "transactionAmount")
                    TextField("メモ（例：スーパーで買い物）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("transactionNote")
                } header: {
                    Text("入出金の記録")
                } footer: {
                    Text("この記録は、選んだ月の家計簿に追加されます。資産の現在評価額や、シミュレーションに使う毎月の予算は変わりません。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MTheme.background)
            .navigationTitle(isExisting ? "記録を編集" : "記録を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveTransaction")
                }
            }
            .onChange(of: kind) { _, newKind in
                category = EntryCategories.defaults(for: newKind)[0]
            }
            .alert("入力を確認してください", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
        .tint(MTheme.teal)
        .interactiveDismissDisabled()
    }

    private func save() {
        guard let parsedAmount = Money.parse(amount), parsedAmount.isFinite, parsedAmount > 0 else {
            return fail("金額は0より大きい数値で入力してください。")
        }
        let updated = LedgerTransaction(id: item.id, date: date, kind: kind, category: category,
                                        amount: parsedAmount, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.saveTransaction(updated) { dismiss() }
        else {
            let message = store.errorMessage ?? "保存できませんでした。もう一度お試しください。"
            store.errorMessage = nil
            fail(message)
        }
    }

    private func fail(_ message: String) {
        validationMessage = message
        showingError = true
    }
}
