import SwiftUI
import UniformTypeIdentifiers

struct HouseholdDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document: HouseholdDocument?
    @State private var pendingRestore: HouseholdState?
    @State private var confirmRestore = false
    @State private var confirmClear = false
    @State private var confirmSample = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 15) {
                    Image(systemName: "leaf.fill").font(.title).foregroundStyle(MTheme.teal).frame(width: 58, height: 58).background(MTheme.pale, in: RoundedRectangle(cornerRadius: 19))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("みらい家計").font(.headline).foregroundStyle(MTheme.ink)
                        Text("今日のお金から、未来の暮らしへ。").font(.caption).foregroundStyle(MTheme.muted)
                        Text("バージョン 1.1").font(.caption2).foregroundStyle(MTheme.muted)
                    }
                }.padding(.vertical, 8)
            }
            Section {
                Button { export() } label: { Label("バックアップを書き出す", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("exportBackup")
                Button { importing = true } label: { Label("バックアップから復元", systemImage: "square.and.arrow.down") }
                Button { store.reload(); errorMessage = store.errorMessage } label: { Label("保存データを再読み込み", systemImage: "arrow.clockwise") }
            } header: { Text("データの保存") } footer: {
                Text("データはこの端末内に保存されます。機種変更の前にバックアップを書き出してください。JSONには資産・家計の情報が含まれます。")
            }
            Section {
                NavigationLink { CalculationNotes() } label: { Label("計算の仕組みと前提", systemImage: "function") }
                Link(destination: URL(string: "https://www.fsa.go.jp/policy/nisa2/know/index.html")!) { Label("NISA制度について（金融庁）", systemImage: "arrow.up.right.square") }
            } header: { Text("シミュレーションについて") }
            Section {
                Button { confirmSample = true } label: { Label("架空のサンプルを読み込む", systemImage: "sparkles") }
                Button(role: .destructive) { confirmClear = true } label: { Label("データを初期化して始める", systemImage: "trash") }.accessibilityIdentifier("resetData")
            } header: { Text("はじめから使う") } footer: {
                Text("どちらも現在の登録内容を置き換えます。必要なデータは先にバックアップしてください。")
            }
        }.scrollContentBackground(.hidden).background(MTheme.background).navigationTitle("設定")
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "みらい家計-backup") { result in
                switch result {
                case .success: successMessage = "バックアップを書き出しました。"
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 50_000_000 else { throw ImportError.tooLarge }
                    let bytes = try Data(contentsOf: url)
                    guard bytes.count <= 50_000_000 else { throw ImportError.tooLarge }
                    pendingRestore = try LedgerRepository.decode(bytes)
                    confirmRestore = true
                } catch { errorMessage = error.localizedDescription }
            }
            .confirmationDialog("バックアップで置き換えますか？", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("このバックアップを復元", role: .destructive) {
                    if let pendingRestore {
                        if store.restore(pendingRestore) { successMessage = "バックアップを復元しました。" }
                        else { errorMessage = store.errorMessage }
                    }
                    pendingRestore = nil
                }
                Button("キャンセル", role: .cancel) { pendingRestore = nil }
            } message: {
                if let pendingRestore { Text("資産 \(pendingRestore.assets.count)件・予算 \(pendingRestore.budgetItems.count)件・記録 \(pendingRestore.transactions.count)件・比較プラン \(pendingRestore.variants.count)件で現在の内容を置き換えます。") }
            }
            .confirmationDialog("すべてのデータを初期化しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("初期化する", role: .destructive) { if !store.clearData() { errorMessage = store.errorMessage } }
                Button("キャンセル", role: .cancel) {}
            } message: { Text("資産・予算・記録・シミュレーション設定・比較プランを削除します。") }
            .confirmationDialog("サンプルに置き換えますか？", isPresented: $confirmSample, titleVisibility: .visible) {
                Button("サンプルを読み込む", role: .destructive) { if !store.loadSample() { errorMessage = store.errorMessage } }
                Button("キャンセル", role: .cancel) {}
            } message: { Text("現在の登録内容を、架空のサンプルデータで置き換えます。") }
            .alert("処理を完了できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .alert("保存しました", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
                Button("OK") { successMessage = nil }
            } message: { Text(successMessage ?? "") }
    }

    private func export() {
        do { document = HouseholdDocument(data: try LedgerRepository.encode(store.data)); exporting = true }
        catch { errorMessage = error.localizedDescription }
    }

    enum ImportError: LocalizedError {
        case tooLarge
        var errorDescription: String? { "50MB以下のバックアップを選択してください。" }
    }
}

private struct CalculationNotes: View {
    var body: some View {
        List {
            Section("毎月のお金の流れ") {
                Text("① 運用資産を年利から換算した月利で運用\n② 毎月の収入 − 支出と、その月の予定を反映\n③ 余剰資金の指定割合を、資産の配分比率で月末に積立\n④ 残りを現金として保有（現金・預金の利息は0%）")
                    .lineSpacing(6)
                Text("月利 = (1 + 年利 ÷ 100)^(1/12) − 1。積立直後の金額に同じ月の運用益を加えません。")
            }
            Section("入力と家計簿の関係") {
                Text("資産には、基準日時点の評価額を入力します。日々の家計簿は振り返り用です。記録を追加しても評価額や将来の予算は自動で変わらないため、残高の二重計上を防ぎます。")
                Text("今後の計算には「毎月の予算」を使います。記録を見ながら予算を更新し、資産の評価額と基準日も定期的に更新してください。")
            }
            Section("利回り・シナリオ") {
                Text("利回りはご自身で置く一定の仮定です。慎重・積極シナリオでは現金以外の年利を標準から −2・+2ポイント調整します。確率や将来の予測を示すものではありません。")
                Text("表示額は売却前の評価額です。税金・手数料・分配金課税は自動計算しません。利回りは必要に応じて費用を考慮した値を入力してください。")
            }
            Section("NISAの扱い") {
                Text("NISAは資産の種類と別に設定する口座区分です。つみたて投資枠は年120万円、成長投資枠は年240万円、簿価総額1,800万円（成長投資枠は内数1,200万円）として計算します。")
                Text("年内に使った枠はシミュレーション設定で入力します。枠を超えた積立は現金に残し、課税口座へ自動振替しません。対象商品の適格性は判定しません。旧NISAは対象外です。")
                Text("売却時の簿価減少に対応し、総枠の再利用は翌年から反映します。年間投資枠は売却しても同じ年には戻りません。")
            }
            Section("赤字・物価の上昇") {
                Text("収支が赤字の月は現金から取り崩し、不足分は運用資産から比例して取り崩します。資産を使い切った後は不足額として累積し、純資産から差し引きます。不足額には借入利息を付けません。")
                Text("物価を考慮した金額は、将来の純資産を設定したインフレ率で割り引いた現在の購買力です。毎月の収入・支出自体は自動で増減させません。")
            }
        }.font(.subheadline).navigationTitle("計算の仕組み").navigationBarTitleDisplayMode(.inline)
    }
}
