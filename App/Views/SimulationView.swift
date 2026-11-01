import SwiftUI
import Charts

struct SimulationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var scenario: ProjectionScenario = .base
    @State private var selectedMonth: Double = 120
    @State private var showingPlan = false

    var body: some View {
        let projection = Result { try ProjectionEngine.project(state: store.data, scenario: scenario) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    comparisonLink
                    scenarioPicker
                    switch projection {
                    case .success(let result):
                        let point = selectedPoint(in: result)
                        projectionCard(result, point: point)
                        goalCard(result)
                        cashflowCard(result)
                        milestonesCard(result)
                        if !store.data.events.isEmpty { eventsCard }
                        assumptionsCard
                    case .failure(let error):
                        ContentUnavailableView {
                            Label("計算条件を確認してください", systemImage: "slider.horizontal.3")
                        } description: {
                            Text(error.localizedDescription)
                        } actions: {
                            Button("プランを編集") { showingPlan = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(MTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPlan) {
                SimulationPlanEditor(plan: store.data.plan, events: store.data.events, nisaUsage: store.data.nisaUsage)
                    .environmentObject(store)
            }
            .onAppear { selectedMonth = Double(store.data.plan.months) }
            .onChange(of: store.data.plan.months) { _, newValue in
                selectedMonth = Double(newValue)
            }
        }
        .tint(MTheme.teal)
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("FUTURE PLANNER")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.3)
                    .foregroundStyle(MTheme.teal)
                Text("未来を描く")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(MTheme.ink)
                Text("毎月の積み重ねを、見える未来に。")
                    .font(.subheadline)
                    .foregroundStyle(MTheme.muted)
            }
            Spacer(minLength: 0)
            Button { showingPlan = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(MTheme.teal)
                    .background(MTheme.card, in: RoundedRectangle(cornerRadius: 17))
            }
            .accessibilityLabel("シミュレーションのプランを編集")
            .accessibilityIdentifier("editPlan")
        }
    }

    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("運用シナリオ")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MTheme.ink)
                Spacer()
                Text(scenarioAdjustment)
                    .font(.caption)
                    .foregroundStyle(MTheme.muted)
            }
            HStack(spacing: 5) {
                ForEach(ProjectionScenario.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { scenario = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: scenarioSymbol(item))
                                .font(.system(size: 11, weight: .bold))
                            Text(item.title).font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(scenario == item ? Color.white : MTheme.muted)
                        .background(scenario == item ? MTheme.forest : .clear, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scenario == item ? .isSelected : [])
                }
            }
            .padding(5)
            .background(MTheme.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var comparisonLink: some View {
        NavigationLink {
            PlanComparisonView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(MTheme.card, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("もしものプランを比較").font(.subheadline.weight(.semibold))
                    Text("支出や積立を変えた未来を並べて見る")
                        .font(.caption).foregroundStyle(MTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .foregroundStyle(MTheme.teal)
            .padding(14)
            .background(MTheme.pale, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("comparePlans")
    }

    private func projectionCard(_ result: ProjectionResult, point: ProjectionPoint) -> some View {
        MCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("計算開始日  \(planDate(store.data.plan.startDate))")
                    .font(.caption)
                    .foregroundStyle(MTheme.muted)
                HStack {
                    Label(point.month == 0 ? "開始時点の純資産" : "\(monthLabel(point.month))経過時の純資産", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MTheme.teal)
                    Spacer()
                    Text(monthDate(point.date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MTheme.muted)
                }
                Text(Money.yen(point.netWorth))
                    .font(.system(size: 37, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .tracking(-1.2)
                    .foregroundStyle(MTheme.ink)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("projectionTotal")
                HStack(spacing: 8) {
                    Image(systemName: point.netWorth >= result.initialAssets ? "arrow.up.right" : "arrow.down.right")
                    Text("開始時点から \(signedYen(point.netWorth - result.initialAssets))")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(point.netWorth >= result.initialAssets ? MTheme.teal : MTheme.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(MTheme.pale, in: Capsule())

                projectionChart(result, point: point)
                    .frame(height: 212)
                    .padding(.top, 6)

                HStack(spacing: 18) {
                    chartKey("純資産", color: MTheme.teal)
                    chartKey("元本＋収支累計", color: MTheme.gold)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    Slider(value: $selectedMonth, in: 0...Double(max(1, store.data.plan.months)), step: 1)
                        .accessibilityLabel("計算開始から何か月後の資産を表示")
                        .accessibilityValue(monthLabel(Int(selectedMonth)))
                        .accessibilityIdentifier("projectionMonthSlider")
                    HStack {
                        Text("開始")
                        Spacer()
                        Text(point.month == 0 ? "開始時点" : "開始から\(monthLabel(point.month))")
                            .fontWeight(.semibold)
                            .foregroundStyle(MTheme.teal)
                        Spacer()
                        Text(monthLabel(store.data.plan.months))
                    }
                    .font(.caption)
                    .foregroundStyle(MTheme.muted)
                }

                Rectangle().fill(MTheme.muted.opacity(0.13)).frame(height: 1)
                HStack(alignment: .top, spacing: 12) {
                    metric("元本＋収支累計", value: Money.compact(result.initialAssets + point.cumulativeContributions), color: MTheme.ink)
                    Spacer(minLength: 0)
                    metric("運用による増減", value: signedCompact(point.cumulativeGrowth), color: point.cumulativeGrowth >= 0 ? MTheme.teal : MTheme.red)
                }
                HStack {
                    Image(systemName: "basket")
                    Text("開始時点の物価で見ると")
                    Spacer()
                    Text(Money.compact(point.realNetWorth)).fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(MTheme.muted)
                .padding(12)
                .background(MTheme.background, in: RoundedRectangle(cornerRadius: 12))

                if point.debt > 0 {
                    Label("資産を使い切るため、不足額 \(Money.yen(point.debt)) を負債として反映しています。", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(MTheme.red)
                } else if let debtMonth = result.firstDebtMonth {
                    Label("計算開始から\(monthLabel(debtMonth))で資金不足が生じる計算です。", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(MTheme.red)
                }
                if point.cumulativeNISAOverflow > 0 {
                    Label("NISAの上限により、累計\(Money.compact(point.cumulativeNISAOverflow))の積立を現金に回しました。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(MTheme.muted)
                }
            }
        }
    }

    private func projectionChart(_ result: ProjectionResult, point: ProjectionPoint) -> some View {
        let ticks = chartTicks(store.data.plan.months)
        return Chart {
            ForEach(result.points, id: \.month) { item in
                AreaMark(
                    x: .value("経過月", item.month),
                    yStart: .value("基準", 0),
                    yEnd: .value("純資産", item.netWorth)
                )
                .foregroundStyle(LinearGradient(colors: [MTheme.teal.opacity(0.18), MTheme.teal.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.linear)
                LineMark(
                    x: .value("経過月", item.month),
                    y: .value("純資産", item.netWorth),
                    series: .value("系列", "純資産")
                )
                .foregroundStyle(MTheme.teal)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.linear)
                LineMark(
                    x: .value("経過月", item.month),
                    y: .value("元本＋収支累計", result.initialAssets + item.cumulativeContributions),
                    series: .value("系列", "元本")
                )
                .foregroundStyle(MTheme.gold)
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
                .interpolationMethod(.linear)
            }
            RuleMark(x: .value("表示月", point.month))
                .foregroundStyle(MTheme.teal.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("表示月", point.month), y: .value("純資産", point.netWorth))
                .foregroundStyle(MTheme.teal)
                .symbolSize(55)
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(1, store.data.plan.months))
        .chartYScale(domain: chartDomain(result))
        .chartXAxis {
            AxisMarks(values: ticks) { axis in
                AxisValueLabel {
                    if let month = axis.as(Int.self) {
                        Text(month == 0 ? "開始" : monthLabel(month))
                            .font(.system(size: 10))
                            .foregroundStyle(MTheme.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { axis in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(MTheme.muted.opacity(0.15))
                AxisValueLabel {
                    if let amount = axis.as(Double.self) {
                        Text(axisMoney(amount)).font(.system(size: 9)).foregroundStyle(MTheme.muted)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("資産推移。計算開始日\(planDate(store.data.plan.startDate))から\(monthLabel(point.month))後の純資産は\(Money.yen(point.netWorth))。スライダーで表示する月を変更できます。")
    }

    private func goalCard(_ result: ProjectionResult) -> some View {
        let goal = store.data.plan.goalAmount
        let final = result.finalPoint
        let progress = goal > 0 ? min(1, max(0, final.netWorth / goal)) : 0
        return MCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    Image(systemName: "flag.checkered")
                        .font(.title3)
                        .foregroundStyle(MTheme.teal)
                        .frame(width: 44, height: 44)
                        .background(MTheme.pale, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("目標資産").font(.caption).foregroundStyle(MTheme.muted)
                        Text(goal > 0 ? Money.yen(goal) : "目標を設定しよう").font(.title3.weight(.bold)).foregroundStyle(MTheme.ink)
                    }
                    Spacer(minLength: 0)
                    if let reached = result.goalReachedMonth {
                        Text(reached == 0 ? "開始時点で達成" : "開始から\(monthLabel(reached))で到達")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MTheme.teal)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if goal > 0 {
                    ProgressView(value: progress)
                        .tint(MTheme.teal)
                        .accessibilityLabel("期間末の目標達成率")
                    Text("期間末（\(monthDate(final.date))）の達成率 \(Int(progress * 100))%")
                        .font(.caption2).foregroundStyle(MTheme.muted)
                }
                if goal == 0 {
                    Button("目標資産を設定") { showingPlan = true }
                        .font(.subheadline.weight(.semibold))
                } else if let reached = result.goalReachedMonth {
                    let date = result.points.first(where: { $0.month == reached })?.date ?? store.data.plan.startDate
                    Text(reached == 0 ? "計算開始時点の純資産が、すでに目標に届いています。" : "この条件なら \(monthDate(date)) に初めて到達する計算です。")
                        .font(.caption)
                        .foregroundStyle(MTheme.muted)
                } else {
                    Text("期間末の\(monthDate(final.date))は目標まで \(Money.compact(max(0, goal - final.netWorth)))。積立額や期間を変えて比べてみましょう。")
                        .font(.caption)
                        .foregroundStyle(MTheme.muted)
                }
            }
        }
    }

    private func cashflowCard(_ result: ProjectionResult) -> some View {
        let hasInvestmentTarget = store.data.assets.contains { $0.kind != .cash && $0.contributionWeight > 0 }
        let investment = hasInvestmentTarget ? max(0, result.monthlySurplus) * store.data.plan.investmentRatioPercent / 100 : 0
        return VStack(alignment: .leading, spacing: 12) {
            MSectionTitle(title: "未来につながるお金", subtitle: "毎月の予算をもとに計算")
            MCard {
                VStack(spacing: 16) {
                    moneyRow("毎月の収支", amount: result.monthlySurplus, symbol: "arrow.left.arrow.right", signed: true)
                    moneyRow("投資へまわす目安", amount: investment, symbol: "chart.line.uptrend.xyaxis")
                    moneyRow("現金に残す目安", amount: max(0, result.monthlySurplus) - investment, symbol: "banknote")
                    Text("投資配分 \(numberText(store.data.plan.investmentRatioPercent))%  ·  物価上昇率 年\(numberText(store.data.plan.annualInflationPercent))%")
                        .font(.caption)
                        .foregroundStyle(MTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if result.monthlySurplus < 0 {
                        Text("毎月の赤字は現金、投資資産の順に取り崩します。")
                            .font(.caption)
                            .foregroundStyle(MTheme.red)
                    } else if !hasInvestmentTarget {
                        Text("積立ウェイトがある投資先がないため、収支の残額はすべて現金に残ります。")
                            .font(.caption)
                            .foregroundStyle(MTheme.muted)
                    }
                }
            }
        }
    }

    private func milestonesCard(_ result: ProjectionResult) -> some View {
        let months = Array(Set([6, 12, 36, 60, 120, 240, store.data.plan.months])).filter { $0 <= store.data.plan.months }.sorted()
        let points = result.points.filter { months.contains($0.month) }
        return VStack(alignment: .leading, spacing: 12) {
            MSectionTitle(title: "未来のチェックポイント", subtitle: "開始日からの経過")
            MCard {
                VStack(spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.element.month) { index, point in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedMonth = Double(point.month) }
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(point.month == Int(selectedMonth) ? MTheme.teal : MTheme.pale)
                                    .frame(width: 5, height: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(monthLabel(point.month))後")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(MTheme.ink)
                                    Text(monthDate(point.date)).font(.caption2).foregroundStyle(MTheme.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(Money.yen(point.netWorth))
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundStyle(MTheme.ink)
                                    Text("運用 \(signedCompact(point.cumulativeGrowth))")
                                        .font(.caption2)
                                        .foregroundStyle(point.cumulativeGrowth >= 0 ? MTheme.teal : MTheme.red)
                                }
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < points.count - 1 { Divider().overlay(MTheme.background) }
                    }
                }
            }
        }
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MSectionTitle(title: "ライフイベント", subtitle: "未来の収支も、計画に")
            MCard {
                VStack(spacing: 16) {
                    ForEach(store.data.events.sorted { $0.month < $1.month }) { event in
                        HStack(spacing: 12) {
                            Image(systemName: event.kind == .income ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(event.kind == .income ? MTheme.teal : MTheme.gold)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.name).font(.subheadline.weight(.medium)).foregroundStyle(MTheme.ink)
                                Text("開始から\(monthLabel(event.month))後\(event.month > store.data.plan.months ? "・試算期間外" : "")")
                                    .font(.caption).foregroundStyle(MTheme.muted)
                            }
                            Spacer()
                            Text("\(event.kind == .income ? "+" : "−")\(Money.compact(event.amount))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MTheme.ink)
                        }
                    }
                }
            }
        }
    }

    private var assumptionsCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                assumption("計算開始日を基準に1か月ずつ試算します。年利を月利に換算し、各期間の運用後に収支を加えます。投資への配分は各資産の積立ウェイトに従います。")
                assumption("毎月の収入・支出は設定額のまま一定とし、昇給や支出額の物価連動は含めません。現金の利息と資金不足による負債の金利は0%として計算します。")
                assumption("資産画面の登録評価額を、設定した計算開始日の資産額として扱います。開始日は自動では変わりません。家計簿の記録は評価額へ自動加算せず、将来の収支は毎月の予算から計算します。")
                assumption("表示額は税金・売買手数料を控除する前の評価額です。NISAの年間枠と保有限度額を超えた積立は現金に残します。売却した分の取得額に対応する保有限度額は翌年に復活させます。")
                assumption("物価調整後の金額は、設定した物価上昇率で計算開始時点の購買力に換算しています。目標判定は物価調整前の純資産で行います。")
                assumption("一定の利回りを仮定した試算です。価格変動や為替変動を予測するものではなく、将来の運用成果を保証しません。")
            }
            .padding(.top, 14)
        } label: {
            Label("計算の前提について", systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MTheme.muted)
        }
        .tint(MTheme.muted)
        .padding(18)
        .background(MTheme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }

    private func assumption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(MTheme.muted).fixedSize(horizontal: false, vertical: true)
    }

    private func selectedPoint(in result: ProjectionResult) -> ProjectionPoint {
        result.points.first(where: { $0.month == min(store.data.plan.months, max(0, Int(selectedMonth))) }) ?? result.finalPoint
    }

    private var scenarioAdjustment: String {
        switch scenario {
        case .conservative: "設定利回り −2ポイント"
        case .base: "資産ごとの設定利回り"
        case .optimistic: "設定利回り ＋2ポイント"
        }
    }

    private func scenarioSymbol(_ item: ProjectionScenario) -> String {
        switch item {
        case .conservative: "leaf"
        case .base: "circle.lefthalf.filled"
        case .optimistic: "arrow.up.right"
        }
    }

    private func chartDomain(_ result: ProjectionResult) -> ClosedRange<Double> {
        let amounts = result.points.flatMap { [$0.netWorth, result.initialAssets + $0.cumulativeContributions] }
        let low = min(0, amounts.min() ?? 0)
        let high = max(10_000, amounts.max() ?? 0)
        return (low < 0 ? low * 1.12 : 0)...(high * 1.12)
    }

    private func chartTicks(_ months: Int) -> [Int] {
        if months < 12 { return Array(Set([0, months / 2, months])).sorted() }
        let interval = [12, 24, 60, 120, 180].first { Double(months) / Double($0) <= 4 } ?? 180
        var ticks = Array(stride(from: 0, through: months, by: interval))
        if let last = ticks.last, months - last >= interval / 2 { ticks.append(months) }
        return ticks
    }

    private func chartKey(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(MTheme.muted)
        }
    }

    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(MTheme.muted)
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(color)
                .minimumScaleFactor(0.65).lineLimit(1)
        }
    }

    private func moneyRow(_ title: String, amount: Double, symbol: String, signed: Bool = false) -> some View {
        HStack {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(MTheme.teal).frame(width: 22)
            Text(title).font(.subheadline).foregroundStyle(MTheme.muted)
            Spacer()
            Text(signed ? signedYen(amount) : Money.yen(amount))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(amount < 0 ? MTheme.red : MTheme.ink)
        }
    }
}

private struct SimulationPlanEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var months: String
    @State private var investmentPercent: String
    @State private var inflationPercent: String
    @State private var goal: String
    @State private var startDate: Date
    @State private var nisaYear: String
    @State private var tsumitateUsed: String
    @State private var growthUsed: String
    @State private var events: [PlannedEvent]
    @State private var editingEvent: EventDraft?
    @State private var errorMessage: String?
    private let originalPlan: SimulationPlan

    init(plan: SimulationPlan, events: [PlannedEvent], nisaUsage: NISAUsage) {
        originalPlan = plan
        _months = State(initialValue: String(plan.months))
        _investmentPercent = State(initialValue: numberText(plan.investmentRatioPercent))
        _inflationPercent = State(initialValue: numberText(plan.annualInflationPercent))
        _goal = State(initialValue: numberText(plan.goalAmount))
        _startDate = State(initialValue: plan.startDate)
        _nisaYear = State(initialValue: String(nisaUsage.calendarYear))
        _tsumitateUsed = State(initialValue: numberText(nisaUsage.tsumitateAnnualUsed))
        _growthUsed = State(initialValue: numberText(nisaUsage.growthAnnualUsed))
        _events = State(initialValue: events)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "シミュレーション期間", text: $months, unit: "か月", identifier: "planMonths")
                    HStack(spacing: 8) {
                        ForEach([12, 60, 120, 240, 360], id: \.self) { value in
                            Button("\(value / 12)年") { months = String(value) }
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(months == String(value) ? MTheme.forest : MTheme.pale, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(months == String(value) ? Color.white : MTheme.teal)
                        }
                    }
                    .buttonStyle(.plain)
                    MoneyField(title: "目標資産", text: $goal, unit: "円", identifier: "planGoal")
                    DatePicker("計算の開始日", selection: $startDate, displayedComponents: .date)
                        .environment(\.calendar, FinanceCalendar.value)
                        .environment(\.timeZone, FinanceCalendar.value.timeZone)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                        .accessibilityIdentifier("planStartDate")
                } header: {
                    Text("未来の目標")
                } footer: {
                    Text("登録した評価額を開始日の資産額として計算します。期間は1〜600か月（50年）。目標は物価調整前の純資産で、0円にすると到達判定を行いません。")
                }
                Section {
                    MoneyField(title: "収支の残額から投資へ", text: $investmentPercent, unit: "%", identifier: "planInvestmentRatio")
                    MoneyField(title: "年間の物価上昇率", text: $inflationPercent, unit: "%", identifier: "planInflation")
                } header: {
                    Text("積立と物価")
                } footer: {
                    Text("投資配分は0〜100%。残りは現金として積み立てます。各資産の利回りや積立ウェイトは「資産」で変更できます。")
                }
                Section {
                    MoneyField(title: "利用額の対象年", text: $nisaYear, unit: "年", identifier: "planNISAYear")
                    MoneyField(title: "つみたて投資枠", text: $tsumitateUsed, unit: "円", identifier: "planNISATsumitate")
                    MoneyField(title: "成長投資枠", text: $growthUsed, unit: "円", identifier: "planNISAGrowth")
                    if Int(nisaYear) != FinanceCalendar.value.component(.year, from: startDate) {
                        Label("対象年が開始年と異なるため、この年間利用額は試算に使われません。", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(MTheme.gold)
                    }
                } header: {
                    Text("NISAの年間利用額")
                } footer: {
                    Text("計算開始前に対象年に購入した金額を入力してください。年間上限はつみたて120万円・成長240万円です。保有限度額は「資産」で入力した取得額をもとに計算します。対象年以外の年の利用額は0円から計算します。")
                }
                Section {
                    ForEach(events.sorted { $0.month < $1.month }) { event in
                        Button { editingEvent = EventDraft(event: event) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.name).foregroundStyle(MTheme.ink)
                                    Text("開始から\(monthLabel(event.month))後・\(event.kind.title)")
                                        .font(.caption).foregroundStyle(MTheme.muted)
                                }
                                Spacer()
                                Text(Money.compact(event.amount)).foregroundStyle(MTheme.ink)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(MTheme.muted)
                            }
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) { events.removeAll { $0.id == event.id } }
                        }
                    }
                    Button { editingEvent = EventDraft() } label: {
                        Label("ライフイベントを追加", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("addPlanEvent")
                } header: {
                    Text("一度だけの収入・支出")
                } footer: {
                    Text("旅行、車の購入、進学費用、臨時収入などを指定した月の収支に反映します。行を左にスワイプすると削除できます。")
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(MTheme.red)
                            .accessibilityIdentifier("planValidationError")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MTheme.background)
            .navigationTitle("未来のプラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold).accessibilityIdentifier("savePlan")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了", action: dismissPlanKeyboard)
                }
            }
            .sheet(item: $editingEvent) { draft in
                PlanEventEditor(draft: draft) { event in
                    if let index = events.firstIndex(where: { $0.id == event.id }) { events[index] = event }
                    else { events.append(event) }
                }
            }
        }
        .tint(MTheme.teal)
    }

    private func save() {
        guard let monthCount = Int(months.trimmingCharacters(in: .whitespacesAndNewlines)), (1...600).contains(monthCount) else {
            errorMessage = "期間は1〜600か月の整数で入力してください。"; return
        }
        guard let investment = inputNumber(investmentPercent), (0...100).contains(investment) else {
            errorMessage = "投資配分は0〜100%で入力してください。"; return
        }
        guard let inflation = inputNumber(inflationPercent), (-20...30).contains(inflation) else {
            errorMessage = "物価上昇率は−20〜30%で入力してください。"; return
        }
        guard let goalAmount = inputNumber(goal), goalAmount >= 0, goalAmount <= 1_000_000_000_000 else {
            errorMessage = "目標資産は0円以上、1兆円以下で入力してください。"; return
        }
        guard let year = Int(nisaYear.trimmingCharacters(in: .whitespacesAndNewlines)), (1900...2200).contains(year),
              let tsumitate = inputNumber(tsumitateUsed), (0...1_200_000).contains(tsumitate),
              let growth = inputNumber(growthUsed), (0...2_400_000).contains(growth) else {
            errorMessage = "NISAの対象年と年間利用額を確認してください。つみたて投資枠は120万円、成長投資枠は240万円までです。"; return
        }
        var plan = originalPlan
        plan.months = monthCount
        plan.investmentRatioPercent = investment
        plan.annualInflationPercent = inflation
        plan.goalAmount = goalAmount
        plan.startDate = startDate
        let usage = NISAUsage(calendarYear: year, tsumitateAnnualUsed: tsumitate, growthAnnualUsed: growth)
        if store.savePlan(plan, events: events, nisaUsage: usage) { dismiss() }
        else { errorMessage = store.errorMessage ?? "保存できませんでした。入力内容と端末の空き容量を確認して、もう一度お試しください。" }
    }
}

private struct EventDraft: Identifiable {
    let id: UUID
    var name: String
    var month: String
    var kind: EntryKind
    var amount: String

    init() {
        id = UUID(); name = ""; month = "12"; kind = .expense; amount = ""
    }

    init(event: PlannedEvent) {
        id = event.id; name = event.name; month = String(event.month); kind = event.kind; amount = numberText(event.amount)
    }
}

private struct PlanEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: EventDraft
    @State private var errorMessage: String?
    let onSave: (PlannedEvent) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("イベント名（例：車の購入）", text: $draft.name)
                        .accessibilityIdentifier("planEventName")
                    Picker("収支の種類", selection: $draft.kind) {
                        Text("支出").tag(EntryKind.expense)
                        Text("収入").tag(EntryKind.income)
                    }
                    .pickerStyle(.segmented)
                    MoneyField(title: "実施する月", text: $draft.month, unit: "か月後", identifier: "planEventMonth")
                    MoneyField(title: "金額", text: $draft.amount, unit: "円", identifier: "planEventAmount")
                } footer: {
                    Text("計算開始日からの経過月を指定します。毎月の収支に加えて、この月だけ反映します。1〜600か月後まで指定できます。")
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(MTheme.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MTheme.background)
            .navigationTitle("ライフイベント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加・更新", action: save).fontWeight(.semibold)
                        .accessibilityIdentifier("savePlanEvent")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了", action: dismissPlanKeyboard)
                }
            }
        }
        .tint(MTheme.teal)
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { errorMessage = "イベント名を1〜80文字で入力してください。"; return }
        guard let month = Int(draft.month.trimmingCharacters(in: .whitespacesAndNewlines)), (1...600).contains(month) else {
            errorMessage = "実施する月は1〜600か月後の整数で入力してください。"; return
        }
        guard let amount = inputNumber(draft.amount), amount > 0, amount <= 1_000_000_000_000 else {
            errorMessage = "金額は0円より大きく、1兆円以下で入力してください。"; return
        }
        onSave(PlannedEvent(id: draft.id, name: name, month: month, kind: draft.kind, amount: amount))
        dismiss()
    }
}

private func monthLabel(_ months: Int) -> String {
    if months < 12 { return "\(months)か月" }
    if months % 12 == 0 { return "\(months / 12)年" }
    return "\(months / 12)年\(months % 12)か月"
}

private func monthDate(_ date: Date) -> String {
    let parts = FinanceCalendar.value.dateComponents([.year, .month], from: date)
    return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
}

private func planDate(_ date: Date) -> String {
    let parts = FinanceCalendar.value.dateComponents([.year, .month, .day], from: date)
    return "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日"
}

@MainActor
private func dismissPlanKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private func numberText(_ value: Double) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...4)))
}

private func inputNumber(_ text: String) -> Double? {
    let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
    guard let number = Double(normalized.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { return nil }
    return number
}

private func signedYen(_ value: Double) -> String {
    "\(value >= 0 ? "+" : "−")\(Money.yen(abs(value)))"
}

private func signedCompact(_ value: Double) -> String {
    "\(value >= 0 ? "+" : "−")\(Money.compact(abs(value)))"
}

private func axisMoney(_ amount: Double) -> String {
    if abs(amount) >= 100_000_000 { return "\(numberText(amount / 100_000_000))億" }
    if abs(amount) >= 10_000 { return "\(numberText(amount / 10_000))万" }
    return numberText(amount)
}
