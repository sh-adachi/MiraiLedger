import SwiftUI
import Charts

struct HouseholdInsightsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var month: Date
    @State private var period = 6
    @State private var showingProposal = false
    init(month: Date = Date()) { _month = State(initialValue: month) }

    private var months: [MonthlyCashflow] { HouseholdAnalytics.months(in: store.data, ending: month, count: period) }
    private var categories: [CategoryBudgetComparison] { HouseholdAnalytics.categories(in: store.data, month: month, kind: .expense) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("HOUSEHOLD INSIGHTS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(MTheme.teal)
                    Text("暮らしのお金を、ふりかえる。")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(MTheme.ink)
                    Text("日々の記録から、収支の変化と使い道を確認できます。")
                        .font(.subheadline).foregroundStyle(MTheme.muted)
                }
                monthSelector
                if let current = months.last {
                    MCard {
                        VStack(spacing: 14) {
                            HStack {
                                amount("記録した収入", current.income, color: MTheme.teal)
                                Spacer()
                                amount("記録した支出", current.expense, color: MTheme.gold)
                            }
                            Divider()
                            HStack {
                                Text("この月の収支").foregroundStyle(MTheme.muted)
                                Spacer()
                                Text(Money.yen(current.surplus)).font(.title3.bold())
                                    .foregroundStyle(current.surplus >= 0 ? MTheme.teal : MTheme.red)
                                    .accessibilityIdentifier("reportMonthlySurplus")
                            }
                            Text("\(current.recordCount)件の記録を集計。未記録の収支は含みません。")
                                .font(.caption).foregroundStyle(MTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                            if FinanceCalendar.value.isDate(month, equalTo: Date(), toGranularity: .month) {
                                Text("今月は月の途中までの記録です。")
                                    .font(.caption).foregroundStyle(MTheme.gold).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                MCard {
                    VStack(alignment: .leading, spacing: 16) {
                        MSectionTitle(title: "収入と支出の推移")
                        Picker("表示期間", selection: $period) {
                            Text("6か月").tag(6); Text("12か月").tag(12)
                        }.pickerStyle(.segmented).accessibilityIdentifier("reportPeriod")
                        Chart(months) { item in
                            BarMark(x: .value("月", item.monthStart, unit: .month), y: .value("金額", item.income))
                                .position(by: .value("種類", "収入")).foregroundStyle(by: .value("種類", "収入"))
                            BarMark(x: .value("月", item.monthStart, unit: .month), y: .value("金額", item.expense))
                                .position(by: .value("種類", "支出")).foregroundStyle(by: .value("種類", "支出"))
                        }
                        .chartForegroundStyleScale(["収入": MTheme.teal, "支出": MTheme.gold])
                        .chartXAxis { AxisMarks(values: .stride(by: .month, count: period == 12 ? 2 : 1)) { value in
                            AxisValueLabel { if let date = value.as(Date.self) { Text(Money.date(date, format: "M月")).font(.caption2) } }
                        } }
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel { if let amount = value.as(Double.self) { Text(Money.compact(amount)).font(.system(size: 9)) } }
                        } }
                        .frame(height: 205)
                        .accessibilityLabel("選択月までの\(period)か月間の記録した収入と支出")
                        Text("期間合計：収入 \(Money.compact(months.reduce(0) { $0 + $1.income })) ／ 支出 \(Money.compact(months.reduce(0) { $0 + $1.expense }))")
                            .font(.caption).foregroundStyle(MTheme.muted)
                    }
                }
                MSectionTitle(title: "カテゴリ別の支出と予算")
                Text("選択した月の記録と、現在登録している月次予算を比較します。過去の予算履歴ではありません。")
                    .font(.caption).foregroundStyle(MTheme.muted)
                if categories.isEmpty {
                    MEmpty(symbol: "chart.bar", title: "まだ集計するデータがありません", message: "家計簿に記録や予算を追加すると、ここに表示されます。")
                } else {
                    MCard {
                        VStack(spacing: 19) {
                            ForEach(categories) { row in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(row.category).font(.subheadline.bold()).foregroundStyle(MTheme.ink)
                                        Spacer()
                                        Text(Money.yen(row.actual)).font(.subheadline.bold()).foregroundStyle(MTheme.ink)
                                    }
                                    if row.hasBudget {
                                        ProgressView(value: min(row.actual, max(1, row.budget)), total: max(1, row.budget))
                                            .tint(row.actual > row.budget ? MTheme.red : MTheme.teal)
                                        HStack {
                                            Text("予算 \(Money.yen(row.budget))")
                                            Spacer()
                                            Text(row.difference > 0 ? "\(Money.yen(row.difference))超過" : "残り \(Money.yen(-row.difference))")
                                                .foregroundStyle(row.difference > 0 ? MTheme.red : MTheme.muted)
                                        }.font(.caption).foregroundStyle(MTheme.muted)
                                    } else {
                                        Text("このカテゴリの予算は未設定です").font(.caption).foregroundStyle(MTheme.muted)
                                    }
                                }
                            }
                        }
                    }
                }
                MCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("実績を、これからの予算へ", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline).foregroundStyle(MTheme.ink)
                        Text("終了した月の記録を平均して、カテゴリごとの予算案を作れます。反映前に変更額を確認できます。")
                            .font(.subheadline).foregroundStyle(MTheme.muted)
                        MPrimaryButton(title: "実績から予算を作る", systemImage: "wand.and.stars") { showingProposal = true }
                            .accessibilityIdentifier("openBudgetProposal")
                    }
                }
            }.padding(20)
        }.background(MTheme.background).navigationTitle("家計レポート").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingProposal = true } label: { Image(systemName: "wand.and.stars") }
                        .accessibilityLabel("実績から予算を作る").accessibilityIdentifier("openBudgetProposalToolbar")
                }
            }
            .sheet(isPresented: $showingProposal) { BudgetProposalView() }
    }

    private var monthSelector: some View {
        HStack {
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 36) }
                .accessibilityLabel("レポートの前の月")
            Spacer()
            Text(Money.date(month, format: "yyyy年M月")).font(.headline).foregroundStyle(MTheme.ink)
            Spacer()
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 36) }
                .accessibilityLabel("レポートの次の月")
        }.padding(8).background(MTheme.card, in: RoundedRectangle(cornerRadius: 17))
    }

    private func amount(_ title: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(MTheme.muted)
            Text(Money.compact(value)).font(.title3.bold()).foregroundStyle(color)
        }
    }

    private func moveMonth(_ step: Int) {
        if let next = FinanceCalendar.value.date(byAdding: .month, value: step, to: month) { month = next }
    }
}

private struct BudgetProposalView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var monthCount = 1
    @State private var ending = FinanceCalendar.value.date(byAdding: .month, value: -1, to: Date())!
    @State private var confirm = false
    @State private var pending: BudgetProposal?
    @State private var errorMessage: String?

    @State private var proposal: BudgetProposal?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("平均する期間", selection: $monthCount) {
                        Text("1か月").tag(1); Text("3か月").tag(3); Text("6か月").tag(6)
                    }.pickerStyle(.segmented).accessibilityIdentifier("proposalMonths")
                    HStack {
                        Text("集計の最終月")
                        Spacer()
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                            .accessibilityLabel("集計の最終月を前に")
                        Text(Money.date(ending, format: "yyyy年M月")).font(.subheadline)
                        Button { move(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                            .accessibilityLabel("集計の最終月を次に").disabled(isLatest)
                    }
                } header: { Text("終了した月を集計") } footer: {
                    Text("記録がない月も0円として平均します。入力が一部だけの場合は、普段の支出より少ない予算になるため、記録状況を確認してください。")
                }
                if let proposal {
                    Section("集計した記録") {
                        Text("\(Money.date(proposal.periodStart)) 〜 \(Money.date(proposal.periodEndExclusive.addingTimeInterval(-1)))")
                            .font(.subheadline)
                        Text("\(proposal.monthCount)か月中 \(proposal.recordedMonthCount)か月に記録・全\(proposal.recordCount)件")
                            .font(.subheadline).foregroundStyle(MTheme.muted)
                        if proposal.canApply {
                            let merged = proposedState(proposal)
                            LabeledContent("反映後の毎月の収入", value: Money.yen(merged.monthlyIncome))
                            LabeledContent("反映後の毎月の支出", value: Money.yen(merged.monthlyExpense))
                            HStack {
                                Text("反映後の毎月の収支")
                                Spacer()
                                Text(Money.yen(merged.monthlySurplus)).foregroundStyle(MTheme.teal).bold()
                                    .accessibilityIdentifier("proposalSurplus")
                            }
                        } else {
                            Text("この期間に記録がないため、予算を作れません。集計期間を変えるか、家計簿に記録を追加してください。")
                                .font(.subheadline).foregroundStyle(MTheme.muted)
                        }
                    }
                    if proposal.canApply {
                        Section {
                            ForEach(proposal.items) { item in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("\(item.category) · \(item.kind.title)").font(.subheadline.bold())
                                    let previous = store.data.budgetItems.filter { $0.kind == item.kind && $0.category == item.category }.reduce(0) { $0 + $1.monthlyAmount }
                                    Text("\(Money.yen(previous)) → \(Money.yen(item.monthlyAmount))／月")
                                        .font(.subheadline).foregroundStyle(MTheme.teal)
                                }.padding(.vertical, 3)
                            }
                        } header: { Text("更新するカテゴリ") } footer: {
                            Text("同じ収支種類・カテゴリの予算は、まとめて平均額に更新します。記録のないカテゴリの予算は残します。資産の評価額と日々の記録は変わりません。平均額は小数を保持し、表示を円単位に丸めます。")
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(MTheme.background)
                .navigationTitle("実績から予算を作る").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("反映") { pending = proposal; confirm = true }
                            .disabled(proposal?.canApply != true).accessibilityIdentifier("applyActualBudget")
                    }
                }
                .alert("この予算案を反映しますか？", isPresented: $confirm) {
                    Button("予算を更新") {
                        if let pending {
                            if store.applyBudgetProposal(pending) { dismiss() }
                            else { errorMessage = store.errorMessage }
                        }
                    }
                    Button("キャンセル", role: .cancel) { pending = nil }
                } message: { Text("表示したカテゴリの予算を更新し、今後のシミュレーションに反映します。") }
                .alert("予算を更新できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("OK") { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
        }.tint(MTheme.teal)
            .onAppear(perform: refreshProposal)
            .onChange(of: monthCount) { _, _ in refreshProposal() }
            .onChange(of: ending) { _, _ in refreshProposal() }
    }

    private func refreshProposal() {
        proposal = try? HouseholdAnalytics.budgetProposal(in: store.data, ending: ending, monthCount: monthCount)
    }

    private var isLatest: Bool {
        let next = FinanceCalendar.value.date(byAdding: .month, value: 1, to: ending)!
        return next >= FinanceCalendar.value.dateInterval(of: .month, for: Date())!.start
    }
    private func move(_ step: Int) {
        if let next = FinanceCalendar.value.date(byAdding: .month, value: step, to: ending) { ending = next }
    }
    private func proposedState(_ proposal: BudgetProposal) -> HouseholdState {
        var next = store.data
        next.budgetItems = proposal.mergedBudgetItems(current: next.budgetItems)
        return next
    }
}
