import SwiftUI

@main
struct MiraiLedgerApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(MTheme.teal)
                .environment(\.calendar, FinanceCalendar.value)
                .environment(\.timeZone, FinanceCalendar.value.timeZone)
                .environment(\.locale, Locale(identifier: "ja_JP"))
        }
    }
}
