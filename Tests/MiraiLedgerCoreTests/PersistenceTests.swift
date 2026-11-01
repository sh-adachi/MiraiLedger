import Foundation
import XCTest
@testable import MiraiLedgerCore

final class PersistenceTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MiraiLedgerTests-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("household.json")
    }

    func testValidatedJSONRoundTripIncludingDatesAndEvents() throws {
        let original = HouseholdState.sample
        let data = try LedgerRepository.encode(original)
        XCTAssertEqual(try LedgerRepository.decode(data), original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
    }

    func testMissingFileAndAtomicSaveReload() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LedgerRepository(url: url)
        XCTAssertNil(try repository.load())
        var state = HouseholdState.sample
        try repository.save(state)
        XCTAssertEqual(try repository.load(), state)
        state.assets[0].balance += 10_000
        try repository.save(state)
        XCTAssertEqual(try repository.load(), state)
    }

    func testCorruptFileIsNeverSilentlyOverwrittenAndCanBeArchived() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalBytes = Data("{ incomplete".utf8)
        try originalBytes.write(to: url)
        let repository = LedgerRepository(url: url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(.empty))
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        let archive = try XCTUnwrap(repository.archiveCorruptFile())
        XCTAssertEqual(try Data(contentsOf: archive), originalBytes)
        try repository.save(.sample)
        XCTAssertNotNil(try repository.load())
        XCTAssertNil(try repository.archiveCorruptFile())
    }

    func testUnknownSchemaAndInvalidImportedMoneyRejected() throws {
        let data = try LedgerRepository.encode(.sample)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 999
        XCTAssertThrowsError(try LedgerRepository.decode(JSONSerialization.data(withJSONObject: json))) { error in
            guard case RepositoryError.unsupportedSchema(999) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        json["schemaVersion"] = 1
        var state = try XCTUnwrap(json["state"] as? [String: Any])
        var assets = try XCTUnwrap(state["assets"] as? [[String: Any]])
        assets[0]["balance"] = -1
        state["assets"] = assets; json["state"] = state
        XCTAssertThrowsError(try LedgerRepository.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testInvalidSavePreservesPreviousValidFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = LedgerRepository(url: url)
        let state = HouseholdState.sample
        try repository.save(state)
        var invalid = state
        invalid.plan.months = 0
        XCTAssertThrowsError(try repository.save(invalid))
        XCTAssertEqual(try repository.load(), state)
    }

    func testOversizedFileIsRejectedBeforeDecoding() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(LedgerRepository.maximumFileSize + 1))
        try handle.close()
        XCTAssertThrowsError(try LedgerRepository(url: url).load()) { error in
            guard case RepositoryError.fileTooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testEncoderCannotProduceBackupBeyondReadableSizeLimit() throws {
        var state = HouseholdState.empty
        let note = String(repeating: "x", count: 2_000)
        state.transactions = (0..<26_000).map { _ in LedgerTransaction(category: "食費", amount: 10, note: note) }
        XCTAssertThrowsError(try LedgerRepository.encode(state)) { error in
            guard case RepositoryError.fileTooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}
