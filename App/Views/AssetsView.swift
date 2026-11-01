import SwiftUI

struct AssetsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingAsset: Asset?
    @State private var deletingAsset: Asset?
    @State private var showingDeleteConfirmation = false
    @State private var operationError = ""
    @State private var showingOperationError = false

    private var total: Double { store.data.totalAssets }
    private var weightedReturn: Double {
        guard total > 0 else { return 0 }
        return store.data.assets.filter { $0.kind != .cash }.reduce(0) { $0 + $1.balance * $1.annualReturnPercent } / total
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    portfolioSummary
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            MSectionTitle(title: "保有している資産")
                            Text("現在の評価額を、未来のスタート地点に。")
                                .font(.caption).foregroundStyle(MTheme.muted)
                        }
                        Spacer(minLength: 8)
                        Text("\(store.data.assets.count)件")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MTheme.muted)
                    }
                    if store.data.assets.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.data.assets) { asset in
                                assetCard(asset)
                            }
                        }
                    }
                    Label("評価額は手動で更新します。日々の家計簿やシミュレーションの結果で、保有資産が自動的に書き換わることはありません。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(MTheme.muted)
                        .lineSpacing(4)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background(MTheme.background)
            .navigationTitle("資産")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingAsset = Asset(name: "", kind: .fund, annualReturnPercent: 3)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("資産を追加")
                    .accessibilityIdentifier("addAsset")
                }
            }
            .sheet(item: $editingAsset) { asset in
                AssetEditor(asset: asset, isExisting: store.data.assets.contains { $0.id == asset.id })
            }
            .confirmationDialog("この資産を削除しますか？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("資産を削除", role: .destructive) {
                    if let asset = deletingAsset, !store.deleteAsset(asset) {
                        operationError = store.errorMessage ?? "削除できませんでした。もう一度お試しください。"
                        store.errorMessage = nil
                        showingOperationError = true
                    }
                    deletingAsset = nil
                }
                Button("キャンセル", role: .cancel) { deletingAsset = nil }
            } message: {
                Text("\(deletingAsset?.name ?? "この資産")を資産一覧と今後のシミュレーションから削除します。")
            }
            .alert("削除できませんでした", isPresented: $showingOperationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(operationError)
            }
        }
        .tint(MTheme.teal)
    }

    private var portfolioSummary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("金融資産 · \(Money.date(store.data.plan.startDate)) 基準")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Image(systemName: "building.columns")
                    .foregroundStyle(MTheme.lime)
            }
            Text(Money.yen(total))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.white)
                .accessibilityIdentifier("totalAssets")
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 3) {
                        ForEach(AssetKind.allCases) { kind in
                            let amount = store.data.assets.filter { $0.kind == kind }.reduce(0) { $0 + $1.balance }
                            if amount > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(kindColor(kind))
                                    .frame(width: max(0, (geometry.size.width - 9) * amount / total))
                            }
                        }
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("想定年利 · 評価額で加重平均")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                    Text(String(format: "%.1f%%", weightedReturn))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MTheme.lime)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("NISAの評価額")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                    Text(Money.compact(store.data.assets.filter { $0.taxTreatment != .taxable }.reduce(0) { $0 + $1.balance }))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(24)
        .background(MTheme.forest, in: RoundedRectangle(cornerRadius: 28))
    }

    private func assetCard(_ asset: Asset) -> some View {
        MCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: kindSymbol(asset.kind))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(MTheme.teal)
                        .frame(width: 46, height: 46)
                        .background(MTheme.background, in: RoundedRectangle(cornerRadius: 15))
                    Button { editingAsset = asset } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(asset.name)
                                .font(.headline)
                                .foregroundStyle(MTheme.ink)
                                .multilineTextAlignment(.leading)
                            Text("\(asset.kind.title) · \(asset.taxTreatment.title)")
                                .font(.caption)
                                .foregroundStyle(MTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(asset.name)を編集")
                    Menu {
                        Button("編集", systemImage: "pencil") { editingAsset = asset }
                        Button("削除", systemImage: "trash", role: .destructive) {
                            deletingAsset = asset
                            showingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(MTheme.muted)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(asset.name)の操作")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.yen(asset.balance))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(MTheme.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(asset.kind == .cash ? "現金・預金" : "年利 \(String(format: "%.1f", asset.annualReturnPercent))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(asset.annualReturnPercent < 0 ? MTheme.red : MTheme.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(MTheme.background, in: Capsule())
                }
                HStack {
                    Text(total > 0 ? "資産の\(String(format: "%.1f", asset.balance / total * 100))%" : "資産の構成比 —")
                    Spacer()
                    Text(asset.kind == .cash ? "現金として保有" : asset.contributionWeight > 0 ? "積立配分 \(String(format: "%g", asset.contributionWeight))" : "積立なし")
                }
                .font(.caption)
                .foregroundStyle(MTheme.muted)
            }
        }
    }

    private var emptyState: some View {
        MCard {
            VStack(spacing: 14) {
                Image(systemName: "leaf")
                    .font(.system(size: 32))
                    .foregroundStyle(MTheme.teal)
                Text("最初の資産を追加しましょう")
                    .font(.headline)
                Text("預貯金、株式、投資信託などを登録すると、\n将来の資産をシミュレーションできます。")
                    .font(.subheadline)
                    .foregroundStyle(MTheme.muted)
                    .multilineTextAlignment(.center)
                Button("資産を追加") { editingAsset = Asset(name: "", kind: .cash, annualReturnPercent: 0) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private func kindSymbol(_ kind: AssetKind) -> String {
        switch kind {
        case .cash: "banknote"
        case .stock: "chart.line.uptrend.xyaxis"
        case .fund: "square.stack.3d.up"
        case .other: "square.grid.2x2"
        }
    }

    private func kindColor(_ kind: AssetKind) -> Color {
        switch kind {
        case .cash: Color(red: 0.80, green: 0.90, blue: 0.74)
        case .stock: Color(red: 0.84, green: 0.73, blue: 0.43)
        case .fund: Color(red: 0.45, green: 0.71, blue: 0.63)
        case .other: Color(red: 0.69, green: 0.76, blue: 0.79)
        }
    }
}

private struct AssetEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let asset: Asset
    let isExisting: Bool
    @State private var name: String
    @State private var kind: AssetKind
    @State private var taxTreatment: TaxTreatment
    @State private var balance: String
    @State private var costBasis: String
    @State private var annualReturn: String
    @State private var contributionWeight: String
    @State private var validationMessage = ""
    @State private var showingError = false

    init(asset: Asset, isExisting: Bool) {
        self.asset = asset
        self.isExisting = isExisting
        _name = State(initialValue: asset.name)
        _kind = State(initialValue: asset.kind)
        _taxTreatment = State(initialValue: asset.taxTreatment)
        _balance = State(initialValue: Money.input(asset.balance))
        _costBasis = State(initialValue: Money.input(asset.costBasis))
        _annualReturn = State(initialValue: Money.input(asset.annualReturnPercent))
        _contributionWeight = State(initialValue: Money.input(asset.contributionWeight))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("資産の情報") {
                    TextField("資産名（例：全世界株式）", text: $name)
                        .accessibilityIdentifier("assetName")
                    Picker("資産の種類", selection: $kind) {
                        ForEach(AssetKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .accessibilityIdentifier("assetKind")
                    if kind != .cash {
                        Picker("口座の区分", selection: $taxTreatment) {
                            ForEach(TaxTreatment.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .accessibilityIdentifier("assetTaxTreatment")
                    }
                }
                Section {
                    MoneyField(title: "現在の評価額", text: $balance, unit: "円", identifier: "assetBalance")
                    if kind != .cash && taxTreatment != .taxable {
                        MoneyField(title: "NISAでの取得額", text: $costBasis, unit: "円", identifier: "assetCostBasis")
                    }
                } header: {
                    Text("いまの金額")
                } footer: {
                    Text(kind == .cash || taxTreatment == .taxable ? "現在の評価額が、シミュレーション開始時の資産額になります。" : "取得額は購入に使った金額です。NISAの非課税保有限度額は、評価額ではなく取得額で判定します。今年の利用額はシミュレーション設定で入力できます。")
                }
                if kind == .cash {
                    Section {
                        Label("現金・預金は、年利0%の現金として計算します。余剰金のうち投資にまわさない分は、現金に加算されます。", systemImage: "info.circle")
                            .font(.subheadline).foregroundStyle(MTheme.muted)
                    }
                } else {
                Section {
                    MoneyField(title: "想定年利", text: $annualReturn, unit: "%", identifier: "assetAnnualReturn")
                    MoneyField(title: "積立配分の重み", text: $contributionWeight, unit: "", identifier: "assetContributionWeight")
                } header: {
                    Text("これからの想定")
                } footer: {
                    Text("年利は−99%から100%で入力します。積立額は配分の重みに応じて割り振ります。同じ重みなら均等、0なら積立しません。想定利回りは将来の運用成果を保証するものではありません。")
                }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MTheme.background)
            .navigationTitle(isExisting ? "資産を編集" : "資産を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveAsset")
                }
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
        guard !trimmedName.isEmpty else { return fail("資産名を入力してください。") }
        guard let parsedBalance = Money.parse(balance), parsedBalance.isFinite, parsedBalance >= 0 else {
            return fail("評価額は0以上の数値で入力してください。")
        }
        guard let parsedCost = kind == .cash || taxTreatment == .taxable ? asset.costBasis : Money.parse(costBasis), parsedCost.isFinite, parsedCost >= 0 else {
            return fail("取得額は0以上の数値で入力してください。")
        }
        guard let parsedReturn = kind == .cash ? 0 : Money.parse(annualReturn), parsedReturn.isFinite, parsedReturn >= -99, parsedReturn <= 100 else {
            return fail("想定年利は−99%から100%の数値で入力してください。")
        }
        guard let parsedWeight = kind == .cash ? 0 : Money.parse(contributionWeight), parsedWeight.isFinite, parsedWeight >= 0, parsedWeight <= 1_000_000 else {
            return fail("積立配分の重みは0から1,000,000の数値で入力してください。")
        }
        let updated = Asset(id: asset.id, name: trimmedName, kind: kind, taxTreatment: kind == .cash ? .taxable : taxTreatment,
                            balance: parsedBalance, costBasis: parsedCost, annualReturnPercent: parsedReturn,
                            contributionWeight: parsedWeight)
        if store.saveAsset(updated) {
            dismiss()
        } else {
            let message = store.errorMessage ?? "保存できませんでした。入力内容を確認して、もう一度お試しください。"
            store.errorMessage = nil
            fail(message)
        }
    }

    private func fail(_ message: String) {
        validationMessage = message
        showingError = true
    }
}
