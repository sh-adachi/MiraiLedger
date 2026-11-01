import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data = HouseholdState.empty
    @Published var errorMessage: String?
    @Published private(set) var isReadOnly = false
    private let repository: LedgerRepository

    init() {
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("--uitesting")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(testing ? "MiraiLedger-UITests" : "MiraiLedger", isDirectory: true)
        if testing && args.contains("--reset-data") { try? FileManager.default.removeItem(at: directory) }
        repository = LedgerRepository(url: directory.appendingPathComponent("household.json"))
        reload()
        if testing && args.contains("--sample-data") && !isReadOnly && data.assets.isEmpty {
            _ = commit(.sample)
        }
    }

    func reload() {
        do {
            data = try repository.load() ?? .empty
            isReadOnly = false
            errorMessage = nil
        } catch {
            isReadOnly = true
            errorMessage = "保存データを読み込めませんでした。元のファイルを保護するため保存を停止しています。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func commit(_ next: HouseholdState) -> Bool {
        guard !isReadOnly else {
            errorMessage = "保存データの読み込みが必要です。設定から再読み込みしてください。"
            return false
        }
        do {
            try repository.save(next)
            data = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveAsset(_ asset: Asset) -> Bool {
        var next = data
        if let i = next.assets.firstIndex(where: { $0.id == asset.id }) { next.assets[i] = asset }
        else { next.assets.append(asset) }
        return commit(next)
    }
    func deleteAsset(_ asset: Asset) -> Bool {
        var next = data; next.assets.removeAll { $0.id == asset.id }; return commit(next)
    }
    func saveBudget(_ item: BudgetItem) -> Bool {
        var next = data
        if let i = next.budgetItems.firstIndex(where: { $0.id == item.id }) { next.budgetItems[i] = item }
        else { next.budgetItems.append(item) }
        return commit(next)
    }
    func deleteBudget(_ item: BudgetItem) -> Bool {
        var next = data; next.budgetItems.removeAll { $0.id == item.id }; return commit(next)
    }
    func saveTransaction(_ item: LedgerTransaction) -> Bool {
        var next = data
        if let i = next.transactions.firstIndex(where: { $0.id == item.id }) { next.transactions[i] = item }
        else { next.transactions.append(item) }
        return commit(next)
    }
    func deleteTransaction(_ item: LedgerTransaction) -> Bool {
        var next = data; next.transactions.removeAll { $0.id == item.id }; return commit(next)
    }
    func savePlan(_ plan: SimulationPlan, events: [PlannedEvent], nisaUsage: NISAUsage? = nil) -> Bool {
        var next = data; next.plan = plan; next.events = events
        if let nisaUsage { next.nisaUsage = nisaUsage }
        return commit(next)
    }
    func saveVariant(_ variant: SimulationVariant) -> Bool {
        do { _ = try VariantCalculator.applying(variant, to: data) }
        catch { errorMessage = error.localizedDescription; return false }
        var next = data
        if let index = next.variants.firstIndex(where: { $0.id == variant.id }) { next.variants[index] = variant }
        else { next.variants.append(variant) }
        return commit(next)
    }
    func deleteVariant(_ variant: SimulationVariant) -> Bool {
        var next = data
        next.variants.removeAll { $0.id == variant.id }
        return commit(next)
    }
    func applyBudgetProposal(_ proposal: BudgetProposal) -> Bool {
        guard proposal.canApply else {
            errorMessage = "対象期間に記録がないため、予算を更新できません。"
            return false
        }
        var next = data
        next.budgetItems = proposal.mergedBudgetItems(current: data.budgetItems)
        return commit(next)
    }
    func loadSample() -> Bool { commit(.sample) }
    func clearData() -> Bool { commit(.empty) }
    func restore(_ state: HouseholdState) -> Bool {
        guard isReadOnly else { return commit(state) }
        var archived: URL?
        do {
            try state.validate()
            archived = try repository.archiveCorruptFile()
            try repository.save(state)
            data = state
            isReadOnly = false
            errorMessage = nil
            return true
        } catch {
            if let archived, !FileManager.default.fileExists(atPath: repository.url.path) {
                try? FileManager.default.moveItem(at: archived, to: repository.url)
            }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
