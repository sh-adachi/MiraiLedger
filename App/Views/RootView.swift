import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var showingRecovery = false
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack { DashboardView(selectedTab: $selectedTab) }
                    .tabItem { Label("ホーム", systemImage: "square.grid.2x2") }.tag(0)
                SimulationView()
                    .tabItem { Label("シミュレーション", systemImage: "chart.xyaxis.line") }.tag(1)
                AssetsView()
                    .tabItem { Label("資産", systemImage: "chart.pie") }.tag(2)
                HouseholdView()
                    .tabItem { Label("家計簿", systemImage: "book.closed") }.tag(3)
                NavigationStack { SettingsView() }
                    .tabItem { Label("設定", systemImage: "slider.horizontal.3") }.tag(4)
            }
            if store.isReadOnly {
                VStack(spacing: 20) {
                    MEmpty(symbol: "externaldrive.badge.exclamationmark", title: "データを読み込めません", message: store.errorMessage ?? "元のデータは保持されています。")
                    MPrimaryButton(title: "再読み込み", systemImage: "arrow.clockwise", action: store.reload)
                    Button("設定からバックアップを復元") { showingRecovery = true }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(MTheme.background)
            }
            if scenePhase != .active {
                VStack(spacing: 16) {
                    Image(systemName: "leaf.fill").font(.system(size: 48)).foregroundStyle(MTheme.lime)
                    Text("みらい家計").font(.title2.bold()).foregroundStyle(.white)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(MTheme.forest).ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingRecovery) {
            NavigationStack {
                SettingsView().toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showingRecovery = false } }
                }
            }
        }
    }
}
