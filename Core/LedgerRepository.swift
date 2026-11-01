import Foundation

public enum RepositoryError: LocalizedError {
    case unsupportedSchema(Int)
    case corruptFile
    case fileTooLarge
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "このデータは未対応のバージョン（\(version)）です。元のファイルは変更されていません。"
        case .corruptFile: "保存データを読み込めませんでした。元のファイルは変更されていません。バックアップから復元できます。"
        case .fileTooLarge: "データファイルが大きすぎます（上限 50 MB）。"
        }
    }
}

public struct LedgerRepository: Sendable {
    public let url: URL
    public static let maximumFileSize = 50_000_000
    private struct Envelope: Codable {
        var schemaVersion: Int
        var savedAt: Date
        var state: HouseholdState
    }
    private struct SchemaHeader: Decodable { var schemaVersion: Int }
    public static var defaultURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("MiraiLedger", isDirectory: true).appendingPathComponent("household.json")
    }
    public init(url: URL = Self.defaultURL) { self.url = url }

    public static func encode(_ state: HouseholdState) throws -> Data {
        try state.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Fractional reference-date seconds preserve dates exactly in backup round trips.
        encoder.dateEncodingStrategy = .deferredToDate
        // The old app rejects version 2 rather than silently dropping comparison plans.
        let data = try encoder.encode(Envelope(schemaVersion: 2, savedAt: Date(), state: state))
        guard data.count <= maximumFileSize else { throw RepositoryError.fileTooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> HouseholdState {
        guard data.count <= maximumFileSize else { throw RepositoryError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let header: SchemaHeader
        do { header = try decoder.decode(SchemaHeader.self, from: data) }
        catch { throw RepositoryError.corruptFile }
        guard (1...2).contains(header.schemaVersion) else { throw RepositoryError.unsupportedSchema(header.schemaVersion) }
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw RepositoryError.corruptFile }
        try envelope.state.validate()
        return envelope.state
    }

    public func load() throws -> HouseholdState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.int64Value > Int64(Self.maximumFileSize) {
            throw RepositoryError.fileTooLarge
        }
        return try Self.decode(Data(contentsOf: url))
    }

    /// Refuse to silently replace malformed data. Recovery can first preserve it with
    /// archiveCorruptFile(), then save a user-selected valid backup or a fresh state.
    public func save(_ state: HouseholdState) throws {
        let data = try Self.encode(state)
        if FileManager.default.fileExists(atPath: url.path) { _ = try load() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    /// Only moves an invalid file; leaves any valid file in place. Returns its archive URL.
    @discardableResult public func archiveCorruptFile() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { _ = try load(); return nil }
        catch {
            let archived = url.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: url, to: archived)
            return archived
        }
    }
}
