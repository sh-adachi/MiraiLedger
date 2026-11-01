import SwiftUI
import Charts

struct PlanComparisonView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedIDs: Set<UUID> = []
    @State private var initializedSelection = false
    @State private var editingVariant: SimulationVariant?
    @State private var deletingVariant: SimulationVariant?
    @State private var errorMessage: String?

    var body: some View {
        let base = Result { try ProjectionEngine.project(state: store.data) }
        let evaluations = evaluateVariants()
        let runs = chartRuns(base: base, evaluations: evaluations)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                introduction
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(MTheme.red)
                }
                if !runs.isEmpty { comparisonChart(runs) }
                switch base {
                case .success(let result): baseCard(result)
                case .failure(let error):
                    MCard {
                        Label("基本プランを計算できません。\(error.localizedDescription)", systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(MTheme.red)
                    }
                }
                HStack {
                    Text("保存したプラン").font(.headline).foregroundStyle(MTheme.ink)
                    Spacer()
                    Text("\(store.data.variants.count) / 20")
                        .font(.caption).foregroundStyle(MTheme.muted)
                }
                if evaluations.isEmpty {
                    emptyState
                } else {
                    Text("グラフには基本プランと、選んだ最大3件を表示します。")
                        .font(.caption).foregroundStyle(MTheme.muted)
                    ForEach(evaluations) { evaluation in
                        variantCard(evaluation, base: base, runs: runs, evaluations: evaluations)
                    }
                }
                Text("設定した利回りが続くと仮定した試算です。金額は税金・手数料控除前の純資産で、将来の成果を保証しません。")
                    .font(.caption).foregroundStyle(MTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(MTheme.background)
        .navigationTitle("プランを比較")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addVariant() } label: { Label("プランを追加", systemImage: "plus") }
                    .disabled(store.data.variants.count >= 20)
                    .accessibilityIdentifier("addVariant")
            }
        }
        .sheet(item: $editingVariant) { variant in
            SimulationVariantEditor(variant: variant) { savedID in
                selectSavedVariant(savedID)
            }
            .environmentObject(store)
        }
        .confirmationDialog("保存した比較プランを削除しますか？", isPresented: Binding(
            get: { deletingVariant != nil },
            set: { if !$0 { deletingVariant = nil } }
        ), titleVisibility: .visible) {
            if let variant = deletingVariant {
                Button("「\(variant.name)」を削除", role: .destructive) {
                    if store.deleteVariant(variant) {
                        selectedIDs.remove(variant.id)
                        errorMessage = nil
                    } else {
                        errorMessage = store.errorMessage ?? "プランを削除できませんでした。"
                    }
                    deletingVariant = nil
                }
            }
            Button("キャンセル", role: .cancel) { deletingVariant = nil }
        }
        .onAppear {
            guard !initializedSelection else { return }
            selectedIDs = Set(evaluations.filter { $0.projection != nil }.prefix(3).map(\.id))
            initializedSelection = true
        }
        .onChange(of: store.data.variants.map(\.id)) { _, ids in
            selectedIDs.formIntersection(Set(ids))
        }
        .tint(MTheme.teal)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A LITTLE CHANGE, A DIFFERENT FUTURE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.5).foregroundStyle(MTheme.teal)
            Text("小さな選択で、未来はどう変わる？")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(MTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("毎月の収入・支出、投資配分、利回りを変えて比較できます。")
                .font(.subheadline).foregroundStyle(MTheme.muted)
            Label("登録済みの資産・予算・イベントと開始日・期間は共通です。保存するのは変更条件だけなので、基本の登録内容を変えると比較結果も更新されます。", systemImage: "link")
                .font(.caption).foregroundStyle(MTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(13)
                .background(MTheme.pale, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var emptyState: some View {
        MCard {
            VStack(spacing: 16) {
                MEmpty(symbol: "arrow.triangle.branch", title: "もうひとつの未来をつくる", message: "食費を月1万円抑えたら。\n収入が増えた分を積み立てたら。\n気になる条件を保存して比べましょう。")
                MPrimaryButton(title: "最初のプランを作る", systemImage: "plus", action: addVariant)
            }
        }
    }

    private func comparisonChart(_ runs: [ComparisonChartRun]) -> some View {
        let amounts = runs.flatMap { $0.projection.points.map(\.netWorth) }
        let low = min(0, amounts.min() ?? 0)
        let high = max(10_000, amounts.max() ?? 0)
        let months = store.data.plan.months
        return MCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(comparisonPeriod(months))の資産推移")
                        .font(.headline).foregroundStyle(MTheme.ink)
                    Text("計算開始日 \(Money.date(store.data.plan.startDate))・標準シナリオを基準に比較")
                        .font(.caption).foregroundStyle(MTheme.muted)
                }
                Chart {
                    ForEach(runs) { run in
                        ForEach(run.projection.points, id: \.month) { point in
                            LineMark(
                                x: .value("経過月", point.month),
                                y: .value("純資産", point.netWorth),
                                series: .value("プラン", run.id)
                            )
                            .foregroundStyle(run.color)
                            .lineStyle(StrokeStyle(lineWidth: run.isBase ? 2.5 : 2, dash: run.isBase ? [5, 3] : []))
                            .interpolationMethod(.linear)
                        }
                    }
                }
                .frame(height: 225)
                .chartLegend(.hidden)
                .chartXScale(domain: 0...max(1, months))
                .chartYScale(domain: (low < 0 ? low * 1.1 : 0)...(high * 1.1))
                .chartXAxis {
                    AxisMarks(values: Array(Set([0, months / 2, months])).sorted()) { value in
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text(month == 0 ? "開始" : comparisonPeriod(month))
                                    .font(.system(size: 10)).foregroundStyle(MTheme.muted)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .foregroundStyle(MTheme.muted.opacity(0.15))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Money.compact(amount)).font(.system(size: 9)).foregroundStyle(MTheme.muted)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("プラン別の資産推移。期間末は、" + runs.map { "\($0.name)が\(Money.yen($0.projection.finalPoint.netWorth))" }.joined(separator: "、"))
                .accessibilityIdentifier("comparisonChart")
                VStack(spacing: 10) {
                    ForEach(runs) { run in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(run.color).frame(width: 16, height: 4)
                            Text(run.name).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(Money.compact(run.projection.finalPoint.netWorth))
                                .fontWeight(.semibold).monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(MTheme.ink)
                    }
                }
                Text("金額は期間末の純資産です。基本プランは破線で表示しています。")
                    .font(.caption2).foregroundStyle(MTheme.muted)
            }
        }
    }

    private func baseCard(_ result: ProjectionResult) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("基本のプラン", systemImage: "house.fill").font(.subheadline.weight(.semibold))
                Spacer()
                Text("共通の出発点").font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Text(Money.yen(result.finalPoint.netWorth))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityIdentifier("comparisonBaseTotal")
            Text("期間末 \(Money.date(result.finalPoint.date, format: "yyyy年M月")) ・ 毎月の収支 \(comparisonSignedYen(result.monthlySurplus))")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
            Text(goalDescription(result)).font(.caption).foregroundStyle(MTheme.lime)
            if let debtMonth = result.firstDebtMonth {
                Label("開始から\(comparisonPeriod(debtMonth))で資金不足", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.white)
            }
        }
        .padding(21).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(MTheme.forest, in: RoundedRectangle(cornerRadius: 23))
    }

    private func variantCard(_ evaluation: VariantEvaluation, base: Result<ProjectionResult, Error>, runs: [ComparisonChartRun], evaluations: [VariantEvaluation]) -> some View {
        let variant = evaluation.variant
        let run = runs.first { $0.id == variant.id.uuidString }
        let isSelected = run != nil
        let validSelectedCount = evaluations.filter { selectedIDs.contains($0.id) && $0.projection != nil }.count
        return MCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(variant.name).font(.headline).foregroundStyle(MTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(variantSummary(variant)).font(.caption).foregroundStyle(MTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("編集", systemImage: "pencil") { editingVariant = variant }
                        Button("削除", systemImage: "trash", role: .destructive) { deletingVariant = variant }
                    } label: {
                        Image(systemName: "ellipsis").font(.headline)
                            .frame(width: 34, height: 32).contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(variant.name)の編集と削除")
                    .accessibilityIdentifier("variantMenu." + variant.name)
                }
                switch evaluation.result {
                case .success(let result):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Money.yen(result.finalPoint.netWorth))
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(MTheme.ink)
                            .accessibilityIdentifier("variantTotal." + variant.name)
                        Spacer(minLength: 0)
                    }
                    if case .success(let baseResult) = base {
                        let difference = result.finalPoint.netWorth - baseResult.finalPoint.netWorth
                        Text("基本との差  \(comparisonSignedYen(difference))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(difference >= 0 ? MTheme.teal : MTheme.red)
                            .accessibilityIdentifier("variantDifference." + variant.name)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("毎月の収支 \(comparisonSignedYen(result.monthlySurplus))")
                        Text(goalDescription(result))
                        if let debtMonth = result.firstDebtMonth {
                            Label("開始から\(comparisonPeriod(debtMonth))で資金不足", systemImage: "exclamationmark.circle")
                                .foregroundStyle(MTheme.red)
                        }
                    }
                    .font(.caption).foregroundStyle(MTheme.muted)
                    HStack {
                        Button {
                            toggleSelection(variant.id, evaluations: evaluations)
                        } label: {
                            Label(isSelected ? "グラフに表示中" : "グラフに追加", systemImage: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? (run?.color ?? MTheme.teal) : MTheme.teal)
                                .padding(.vertical, 9).padding(.horizontal, 11)
                                .background(MTheme.pale, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelected && validSelectedCount >= 3)
                        .opacity(!isSelected && validSelectedCount >= 3 ? 0.5 : 1)
                        .accessibilityLabel("\(variant.name)を\(isSelected ? "グラフから外す" : "グラフに追加")")
                        Spacer()
                        Button("編集") { editingVariant = variant }
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("editVariant." + variant.name)
                    }
                case .failure(let error):
                    Label("基本の登録内容が変わったため、この条件では比較できません。", systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(MTheme.red)
                    Text(error.localizedDescription).font(.caption).foregroundStyle(MTheme.muted)
                    Button("条件を見直す") { editingVariant = variant }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func evaluateVariants() -> [VariantEvaluation] {
        store.data.variants.map { variant in
            VariantEvaluation(variant: variant, result: Result {
                let state = try VariantCalculator.applying(variant, to: store.data)
                return try ProjectionEngine.project(state: state)
            })
        }
    }

    private func chartRuns(base: Result<ProjectionResult, Error>, evaluations: [VariantEvaluation]) -> [ComparisonChartRun] {
        var runs: [ComparisonChartRun] = []
        if case .success(let projection) = base {
            runs.append(ComparisonChartRun(id: "base", name: "基本のプラン", color: MTheme.teal, projection: projection, isBase: true))
        }
        let colors = [MTheme.gold, Color(light: 0x487DA3, dark: 0x96C9EF), Color(light: 0x9A618B, dark: 0xD7ACCD)]
        let selected = evaluations.filter { selectedIDs.contains($0.id) && $0.projection != nil }.prefix(3)
        for (index, item) in selected.enumerated() {
            guard let projection = item.projection else { continue }
            runs.append(ComparisonChartRun(id: item.id.uuidString, name: item.variant.name, color: colors[index], projection: projection, isBase: false))
        }
        return runs
    }

    private func toggleSelection(_ id: UUID, evaluations: [VariantEvaluation]) {
        selectedIDs.formIntersection(Set(evaluations.filter { $0.projection != nil }.map(\.id)))
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else if selectedIDs.count < 3 { selectedIDs.insert(id) }
    }

    private func addVariant() {
        guard store.data.variants.count < 20 else { return }
        editingVariant = SimulationVariant(name: "", investmentRatioPercent: store.data.plan.investmentRatioPercent)
    }

    private func selectSavedVariant(_ id: UUID) {
        if !selectedIDs.contains(id) && selectedIDs.count >= 3,
           let replaced = store.data.variants.reversed().first(where: { selectedIDs.contains($0.id) && $0.id != id }) {
            selectedIDs.remove(replaced.id)
        }
        selectedIDs.insert(id)
    }

    private func goalDescription(_ result: ProjectionResult) -> String {
        guard store.data.plan.goalAmount > 0 else { return "目標資産は未設定です" }
        guard let month = result.goalReachedMonth else { return "目標 \(Money.compact(store.data.plan.goalAmount))には期間内に届きません" }
        if month == 0 { return "計算開始時点で目標に届いています" }
        let date = result.points.first { $0.month == month }?.date ?? result.finalPoint.date
        return "目標に初めて到達：\(Money.date(date, format: "yyyy年M月"))（開始から\(comparisonPeriod(month))）"
    }

    private func variantSummary(_ variant: SimulationVariant) -> String {
        var parts: [String] = []
        if variant.monthlyIncomeAdjustment != 0 { parts.append("月の収入 \(comparisonSignedYen(variant.monthlyIncomeAdjustment))") }
        if variant.monthlyExpenseAdjustment != 0 { parts.append("月の支出 \(comparisonSignedYen(variant.monthlyExpenseAdjustment))") }
        parts.append("投資配分 \(Money.decimal(variant.investmentRatioPercent))%")
        if variant.annualReturnAdjustment != 0 { parts.append("年利 \(variant.annualReturnAdjustment >= 0 ? "+" : "−")\(Money.decimal(abs(variant.annualReturnAdjustment)))ポイント") }
        return parts.joined(separator: " ・ ")
    }
}

private struct VariantEvaluation: Identifiable {
    let variant: SimulationVariant
    let result: Result<ProjectionResult, Error>
    var id: UUID { variant.id }
    var projection: ProjectionResult? { try? result.get() }
}

private struct ComparisonChartRun: Identifiable {
    let id: String
    let name: String
    let color: Color
    let projection: ProjectionResult
    let isBase: Bool
}

private struct SimulationVariantEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var incomeAdjustment: String
    @State private var expenseAdjustment: String
    @State private var investmentRatio: String
    @State private var returnAdjustment: String
    @State private var errorMessage: String?
    let variantID: UUID
    let onSaved: (UUID) -> Void

    init(variant: SimulationVariant, onSaved: @escaping (UUID) -> Void) {
        variantID = variant.id
        self.onSaved = onSaved
        _name = State(initialValue: variant.name)
        _incomeAdjustment = State(initialValue: Money.input(variant.monthlyIncomeAdjustment))
        _expenseAdjustment = State(initialValue: Money.input(variant.monthlyExpenseAdjustment))
        _investmentRatio = State(initialValue: Money.input(variant.investmentRatioPercent))
        _returnAdjustment = State(initialValue: Money.input(variant.annualReturnAdjustment))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：支出を月1万円減らす", text: $name)
                        .accessibilityIdentifier("variantName")
                } header: { Text("プラン名") }
                Section {
                    SignedVariantField(title: "収入の増減", text: $incomeAdjustment, unit: "円 / 月", identifier: "variantIncomeAdjustment")
                    SignedVariantField(title: "支出の増減", text: $expenseAdjustment, unit: "円 / 月", identifier: "variantExpenseAdjustment")
                    Button("支出を月1万円減らす条件を入れる") {
                        expenseAdjustment = "-10000"
                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = "支出を月1万円減らす" }
                    }
                    .font(.subheadline)
                } header: { Text("毎月の収支を変える") }
                footer: { Text("現在の基本予算から増やす額はプラス、減らす額はマイナスで入力します。±ボタンで符号を切り替えられます。") }
                Section {
                    MoneyField(title: "残額から投資へ", text: $investmentRatio, unit: "%", identifier: "variantInvestmentRatio")
                    SignedVariantField(title: "設定年利の増減", text: $returnAdjustment, unit: "ポイント", identifier: "variantReturnAdjustment")
                } header: { Text("積立と運用の条件") }
                footer: { Text("投資配分は0〜100%。年利の増減は−20〜＋20ポイントで、現金以外の全資産に加えます。例：設定年利4%に＋1ポイントなら5%です。適用後の年利は−99〜100%の範囲に収めてください。") }
                Section {
                    preview
                } header: { Text("この条件での毎月の予算") }
                footer: { Text("現在登録されている資産、予算、イベント、NISA利用額、開始日と期間を共有して計算します。保存後に基本の登録内容を変えると、このプランも新しい内容をもとに再計算されます。保存は基本プランを書き換えません。") }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(MTheme.red).font(.subheadline)
                            .accessibilityIdentifier("variantValidationError")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MTheme.background)
            .navigationTitle("比較プランの条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold).accessibilityIdentifier("saveVariant")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .tint(MTheme.teal)
    }

    @ViewBuilder private var preview: some View {
        if let variant = parsedVariant(preview: true) {
            let outcome = Result { try VariantCalculator.applying(variant, to: store.data) }
            switch outcome {
            case .success(let state):
                previewRow("収入", value: state.monthlyIncome)
                previewRow("支出", value: state.monthlyExpense)
                previewRow("収支の残額", value: state.monthlySurplus)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(MTheme.red)
            }
        } else {
            Text("数値を入力すると、変更後の予算が表示されます。")
                .font(.caption).foregroundStyle(MTheme.muted)
        }
    }

    private func previewRow(_ title: String, value: Double) -> some View {
        HStack {
            Text(title).foregroundStyle(MTheme.muted)
            Spacer()
            Text(Money.yen(value)).fontWeight(.semibold).foregroundStyle(value < 0 ? MTheme.red : MTheme.ink)
        }
    }

    private func parsedVariant(preview: Bool) -> SimulationVariant? {
        guard let income = Money.parse(incomeAdjustment), let expense = Money.parse(expenseAdjustment),
              let ratio = Money.parse(investmentRatio), let annualReturn = Money.parse(returnAdjustment) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SimulationVariant(id: variantID, name: preview && trimmedName.isEmpty ? "編集中のプラン" : trimmedName,
                                 monthlyIncomeAdjustment: income, monthlyExpenseAdjustment: expense,
                                 investmentRatioPercent: ratio, annualReturnAdjustment: annualReturn)
    }

    private func save() {
        guard let variant = parsedVariant(preview: false) else {
            errorMessage = "増減額・投資配分・年利の増減を有効な数値で入力してください。"; return
        }
        do {
            _ = try VariantCalculator.applying(variant, to: store.data)
            guard store.saveVariant(variant) else {
                errorMessage = store.errorMessage ?? "プランを保存できませんでした。"; return
            }
            onSaved(variant.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SignedVariantField: View {
    let title: String
    @Binding var text: String
    let unit: String
    let identifier: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 6)
            Button {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()) : "-" + (trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed)
            } label: {
                Image(systemName: "plus.forwardslash.minus").font(.caption)
                    .frame(width: 28, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(title)の正負を切り替える")
            .accessibilityIdentifier(identifier + "Sign")
            TextField("0", text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(minWidth: 55, maxWidth: 130)
                .accessibilityIdentifier(identifier)
            Text(unit).font(.caption).foregroundStyle(MTheme.muted)
        }
    }
}

private func comparisonPeriod(_ months: Int) -> String {
    if months == 0 { return "開始時点" }
    if months < 12 { return "\(months)か月" }
    if months % 12 == 0 { return "\(months / 12)年" }
    return "\(months / 12)年\(months % 12)か月"
}

private func comparisonSignedYen(_ value: Double) -> String {
    "\(value >= 0 ? "+" : "−")\(Money.yen(abs(value)))"
}
