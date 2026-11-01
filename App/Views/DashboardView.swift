import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedTab: Int
    private var hasData: Bool { !store.data.assets.isEmpty || !store.data.budgetItems.isEmpty }
    private var projection: ProjectionResult? { try? ProjectionEngine.project(state: store.data) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if store.data.isSampleData { sampleBadge }
                if hasData {
                    wealthCard
                    cashflow
                    outlook
                    nextSteps
                } else { welcome }
                Text("今日のお金を知って、これからを育てる。")
                    .font(.caption).foregroundStyle(MTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 22)
        }.background(MTheme.background).toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("MIRAI  /  お金の見通し").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(MTheme.teal)
                Text("みらい家計").font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(MTheme.ink)
            }
            Spacer()
            Image(systemName: "leaf.fill").font(.system(size: 24, weight: .light)).foregroundStyle(MTheme.teal)
                .frame(width: 52, height: 52).background(MTheme.pale, in: RoundedRectangle(cornerRadius: 19))
        }
    }

    private var sampleBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("サンプルをもとにしたプラン")
        }.font(.caption).foregroundStyle(MTheme.teal).padding(.horizontal, 13).padding(.vertical, 9)
            .background(MTheme.pale, in: Capsule())
    }

    private var wealthCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("登録した金融資産", systemImage: "circle.grid.2x2.fill").font(.subheadline).foregroundStyle(.white.opacity(0.76))
                Spacer()
                Text(Money.date(store.data.plan.startDate)).font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            Text(Money.yen(store.data.totalAssets)).font(.system(size: 37, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).monospacedDigit()
                .accessibilityIdentifier("currentTotal")
            HStack(spacing: 0) {
                metric("現金・預金", value: Money.compact(store.data.assets.filter { $0.kind == .cash }.reduce(0) { $0 + $1.balance }))
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 30).padding(.horizontal, 22)
                metric("運用中", value: Money.compact(store.data.assets.filter { $0.kind != .cash }.reduce(0) { $0 + $1.balance }))
                Spacer(minLength: 0)
            }
        }.padding(24).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .topTrailing) {
                    MTheme.forest
                    Circle().stroke(MTheme.lime.opacity(0.09), lineWidth: 30).frame(width: 185, height: 185).offset(x: 62, y: 67)
                    Circle().stroke(MTheme.lime.opacity(0.07), lineWidth: 1).frame(width: 240, height: 240).offset(x: 80, y: 40)
                }.clipShape(RoundedRectangle(cornerRadius: 28))
            }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.65))
            Text(value).font(.system(.headline, design: .rounded))
        }
    }

    private var cashflow: some View {
        VStack(spacing: 13) {
            MSectionTitle(title: "毎月のお金の流れ", subtitle: "登録した予算から")
            MCard {
                VStack(spacing: 16) {
                    HStack {
                        cashLabel("収入", amount: store.data.monthlyIncome, symbol: "arrow.down.left", color: MTheme.teal)
                        Spacer()
                        cashLabel("支出", amount: store.data.monthlyExpense, symbol: "arrow.up.right", color: MTheme.gold)
                    }
                    Rectangle().fill(MTheme.pale).frame(height: 1)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("未来に回せるお金").font(.subheadline.bold()).foregroundStyle(MTheme.ink)
                            Text("収入 − 支出").font(.caption).foregroundStyle(MTheme.muted)
                        }
                        Spacer()
                        Text(Money.yen(store.data.monthlySurplus)).font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(store.data.monthlySurplus >= 0 ? MTheme.teal : MTheme.red).minimumScaleFactor(0.6).lineLimit(1)
                    }
                }
            }
        }
    }

    private func cashLabel(_ title: String, amount: Double, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.subheadline.bold()).foregroundStyle(color).frame(width: 34, height: 34).background(color.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(MTheme.muted)
                Text(Money.compact(amount)).font(.system(.headline, design: .rounded)).foregroundStyle(MTheme.ink)
            }
        }
    }

    private var outlook: some View {
        VStack(spacing: 13) {
            MSectionTitle(title: "この先の見通し", subtitle: "標準シナリオ")
            if let projection, let last = projection.points.last {
                MCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("基準日から\(period(last.month))の資産").font(.caption).foregroundStyle(MTheme.muted)
                                Text(Money.compact(last.netWorth)).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(MTheme.teal)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.title3).foregroundStyle(MTheme.teal)
                        }
                        Chart(projection.points, id: \.month) { point in
                            AreaMark(x: .value("月", point.month), yStart: .value("基準", min(0, projection.points.map(\.netWorth).min() ?? 0)), yEnd: .value("資産", point.netWorth))
                                .foregroundStyle(LinearGradient(colors: [MTheme.teal.opacity(0.15), MTheme.teal.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("月", point.month), y: .value("資産", point.netWorth)).foregroundStyle(MTheme.teal).lineStyle(StrokeStyle(lineWidth: 2.5))
                        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 95).accessibilityLabel("現在から\(period(last.month))までの資産推移")
                        HStack {
                            Text("開始時点"); Spacer(); Text(period(last.month))
                        }.font(.caption2).foregroundStyle(MTheme.muted)
                        if let month = projection.goalReachedMonth {
                            Label(month == 0 ? "目標は基準日時点で達成" : "目標へ、基準日から\(period(month))に到達", systemImage: "flag.fill")
                                .font(.caption.bold()).foregroundStyle(MTheme.teal)
                        } else if store.data.plan.goalAmount > 0 {
                            Text("目標 \(Money.compact(store.data.plan.goalAmount))・条件を変えて比較できます")
                                .font(.caption).foregroundStyle(MTheme.muted)
                        } else {
                            Text("積立額や期間を変えて、未来を比べてみましょう")
                                .font(.caption).foregroundStyle(MTheme.muted)
                        }
                        MPrimaryButton(title: "未来をシミュレーション", systemImage: "chart.xyaxis.line") { selectedTab = 1 }
                    }
                }
            }
        }
    }

    private var nextSteps: some View {
        Button { selectedTab = 3 } label: {
            HStack(spacing: 13) {
                Image(systemName: "book.closed.fill").font(.title3).foregroundStyle(MTheme.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("日々の支出も、ここに。").font(.subheadline.bold()).foregroundStyle(MTheme.ink)
                    Text("記録を振り返って、毎月の予算を整える").font(.caption).foregroundStyle(MTheme.muted)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(MTheme.muted)
            }.padding(18).background(MTheme.pale, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 19) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 44, weight: .light)).foregroundStyle(MTheme.lime)
                Text("お金のこれからを、\n見えるかたちに。").font(.system(size: 30, weight: .bold, design: .rounded)).lineSpacing(7).foregroundStyle(.white)
                Text("いまの資産と毎月の家計から、\nあなたの未来をシミュレーション。").font(.subheadline).lineSpacing(5).foregroundStyle(.white.opacity(0.75))
            }.padding(27).frame(maxWidth: .infinity, alignment: .leading).background(MTheme.forest, in: RoundedRectangle(cornerRadius: 28))
            MSectionTitle(title: "2つの入力から、はじめよう")
            setupRow("01", title: "いまの資産を登録", detail: "預金・株式・投資信託・NISA", symbol: "chart.pie.fill", tab: 2)
            setupRow("02", title: "毎月の収入と支出を入力", detail: "手取り収入・家賃・食費など", symbol: "banknote.fill", tab: 3)
            Button { _ = store.loadSample() } label: {
                Label("サンプルで体験する", systemImage: "sparkles").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(17)
            }.buttonStyle(.plain).foregroundStyle(MTheme.teal).background(MTheme.pale, in: RoundedRectangle(cornerRadius: 17)).accessibilityIdentifier("loadSample")
            Text("データはこの端末に保存されます。\nサンプルは架空の数値で、設定から初期化できます。")
                .font(.caption).foregroundStyle(MTheme.muted).lineSpacing(4)
        }
    }

    private func setupRow(_ number: String, title: String, detail: String, symbol: String, tab: Int) -> some View {
        Button { selectedTab = tab } label: {
            MCard {
                HStack(spacing: 14) {
                    Text(number).font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(MTheme.teal)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.subheadline.bold()).foregroundStyle(MTheme.ink)
                        Text(detail).font(.caption).foregroundStyle(MTheme.muted)
                    }
                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(MTheme.muted)
                }
            }
        }.buttonStyle(.plain)
    }

    private func period(_ month: Int) -> String {
        if month == 0 { return "現在" }
        return month.isMultiple(of: 12) ? "\(month / 12)年後" : "\(month)か月後"
    }
}
