import SwiftUI

enum MTheme {
    static let background = Color(light: 0xF5F5EF, dark: 0x101F1E)
    static let card = Color(light: 0xFFFFFF, dark: 0x1D302E)
    static let ink = Color(light: 0x183F3B, dark: 0xEDF4EC)
    static let muted = Color(light: 0x74847C, dark: 0xA1B5AE)
    static let teal = Color(light: 0x23665B, dark: 0x8ECEB8)
    static let gold = Color(light: 0xAE7A34, dark: 0xE0BA77)
    static let red = Color(light: 0xB04E42, dark: 0xF09D8D)
    static let pale = Color(light: 0xEAF0E7, dark: 0x2B433B)
    static let lime = Color(red: 0.84, green: 0.93, blue: 0.57)
    static let forest = Color(red: 0.075, green: 0.24, blue: 0.22)
}

extension Color {
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct MCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(MTheme.ink)
            Spacer(minLength: 10)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(MTheme.muted) }
        }
    }
}

enum Money {
    static func yen(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "ja_JP"))) + "円"
    }
    static func compact(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        if magnitude >= 100_000_000 { return decimal(value / 100_000_000) + "億円" }
        if magnitude >= 10_000 { return decimal(value / 10_000) + "万円" }
        return yen(value)
    }
    static func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    static func date(_ value: Date) -> String {
        date(value, format: "yyyy/M/d")
    }
    static func date(_ value: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = FinanceCalendar.value
        formatter.timeZone = FinanceCalendar.value.timeZone
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = format
        return formatter.string(from: value)
    }
    static func input(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(value)
    }
    static func parse(_ text: String) -> Double? {
        let normalized = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

struct MoneyField: View {
    let title: String
    @Binding var text: String
    var unit: String = "円"
    let identifier: String
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            if unit == "%" {
                Button {
                    if text.hasPrefix("-") { text.removeFirst() }
                    else { text = "-" + text }
                } label: { Image(systemName: "plus.forwardslash.minus") }
                    .font(.caption).buttonStyle(.borderless).accessibilityLabel("\(title)の正負を切り替える")
            }
            TextField("0", text: $text).multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad).frame(minWidth: 55, maxWidth: 145)
                .accessibilityIdentifier(identifier)
            Text(unit).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct MEmpty: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(MTheme.teal)
                .frame(width: 70, height: 70).background(MTheme.pale, in: Circle())
            Text(title).font(.headline).foregroundStyle(MTheme.ink)
            Text(message).font(.subheadline).foregroundStyle(MTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct MPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.subheadline.bold())
                .frame(maxWidth: .infinity).padding(.vertical, 15)
        }.buttonStyle(.plain).foregroundStyle(.white)
            .background(MTheme.forest, in: RoundedRectangle(cornerRadius: 17))
    }
}
