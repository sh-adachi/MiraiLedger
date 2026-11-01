import Foundation

public enum VariantCalculator {
    /// Builds an independent calculation input from today's household data. Common
    /// events, start date, horizon, goal, inflation and NISA usage remain identical.
    /// Use ProjectionEngine.project(state:) on the result for a comparable projection.
    public static func applying(_ variant: SimulationVariant, to state: HouseholdState) throws -> HouseholdState {
        try state.validate()
        try variant.validate()
        var result = state
        result.variants = []
        result.plan.investmentRatioPercent = variant.investmentRatioPercent

        try adjustBudget(variant.monthlyIncomeAdjustment, kind: .income, in: &result)
        try adjustBudget(variant.monthlyExpenseAdjustment, kind: .expense, in: &result)
        for index in result.assets.indices where result.assets[index].kind != .cash {
            let rate = result.assets[index].annualReturnPercent + variant.annualReturnAdjustment
            guard (-99...100).contains(rate) else {
                throw ValidationError.invalid("「\(result.assets[index].name)」の調整後の年利が -99% から 100% の範囲を超えています。年利調整を見直してください。")
            }
            result.assets[index].annualReturnPercent = rate
        }
        try result.validate()
        return result
    }

    private static func adjustBudget(_ adjustment: Double, kind: EntryKind, in state: inout HouseholdState) throws {
        guard adjustment != 0 else { return }
        let current = kind == .income ? state.monthlyIncome : state.monthlyExpense
        guard current + adjustment >= 0 else {
            throw ValidationError.invalid("調整後の毎月の\(kind.title)が 0 円未満になります。減額を現在の\(kind.title)以内にしてください。")
        }
        if adjustment < 0 {
            // A reduction is spread over existing items, preserving nonnegative values
            // and their relative proportions in this temporary comparison input.
            let factor = (current + adjustment) / current
            for index in state.budgetItems.indices where state.budgetItems[index].kind == kind {
                state.budgetItems[index].monthlyAmount *= factor
            }
        } else {
            // Reuse existing items' capacity to avoid an artificial extra-row limit.
            var remaining = adjustment
            for index in state.budgetItems.indices where state.budgetItems[index].kind == kind {
                let addition = min(remaining, 1_000_000_000_000_000 - state.budgetItems[index].monthlyAmount)
                state.budgetItems[index].monthlyAmount += addition
                remaining -= addition
                if remaining == 0 { break }
            }
            if remaining > 0 {
                state.budgetItems.append(BudgetItem(name: "比較プランの\(kind.title)調整", category: "比較用", kind: kind, monthlyAmount: remaining))
            }
        }
    }
}
