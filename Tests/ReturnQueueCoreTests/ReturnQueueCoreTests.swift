import Foundation
import XCTest
@testable import ReturnQueueCore

final class ReturnQueueCoreTests: XCTestCase {
    private func item() -> ReturnItem {
        ReturnItem(
            title: "Running shoes", merchant: "Example Store", amountCents: 12_999,
            dropOffLocation: "Main Street counter", deadline: Date(timeIntervalSince1970: 1_800_000_000),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
    }

    func testMoneyParsesExactCentsWithoutRounding() throws {
        let inputs = ["0": 0, "0.01": 1, "19.9": 1_990, "19.99": 1_999, "1000000.00": 100_000_000]
        for (input, expected) in inputs {
            XCTAssertEqual(try Money.cents(from: input), expected, input)
        }
        let highest = "\(Int.max / 100).\(Int.max % 100)"
        XCTAssertEqual(try Money.cents(from: highest), Int.max)
        XCTAssertEqual(Money.formatted(1), "$0.01")
        XCTAssertEqual(Money.formatted(1_999), "$19.99")
        XCTAssertEqual(Money.formatted(-1), "-$0.01")
        XCTAssertFalse(Money.formatted(Int.min).isEmpty)
    }

    func testMoneyRejectsMalformedAndOverflowInput() {
        for input in ["", " ", " 12.99", "12.99 ", "$12", "1,200", "-1", "+1", "1e2", ".50", "1.", "1.001", "1.2.3", "NaN", "１２"] {
            XCTAssertThrowsError(try Money.cents(from: input), input)
        }
        for input in [String(Int.max), "\(Int.max / 100).99", String(repeating: "9", count: 10_000)] {
            XCTAssertThrowsError(try Money.cents(from: input), input.prefix(50).description)
        }
    }

    func testRequiredFieldsAndAmountBounds() throws {
        var record = item()
        record.title = " \nRunning shoes\t"
        XCTAssertEqual(try record.validated().title, "Running shoes")
        for keyPath in [\ReturnItem.title, \ReturnItem.merchant, \ReturnItem.dropOffLocation] {
            var invalid = item()
            invalid[keyPath: keyPath] = " \n\t"
            XCTAssertThrowsError(try invalid.validated())
        }
        for amount in [Int.min, -1, 0, 100_000_001, Int.max] {
            var invalid = item()
            invalid.amountCents = amount
            XCTAssertThrowsError(try invalid.validated())
        }
        record.amountCents = 100_000_000
        XCTAssertNoThrow(try record.validated())
    }

    func testPartialAndFullRefundRules() throws {
        var record = item()
        record.status = .droppedOff
        record.refundReceivedCents = 2_999
        XCTAssertEqual(try record.validated().remainingRefundCents, 10_000)
        record.status = .refunded
        XCTAssertThrowsError(try record.validated()) { error in
            XCTAssertEqual(error as? ReturnQueueError, .incompleteRefund)
        }
        record.refundReceivedCents = record.amountCents
        XCTAssertEqual(try record.validated().remainingRefundCents, 0)
        for refund in [-1, record.amountCents + 1, Int.max] {
            record.refundReceivedCents = refund
            XCTAssertThrowsError(try record.validated())
        }
    }

    func testArchiveRejectsDuplicateIDsUnsupportedVersionsAndInvalidValues() throws {
        let record = item()
        XCTAssertThrowsError(try ArchiveCodec.encode([record, record])) { error in
            XCTAssertEqual(error as? ReturnQueueError, .duplicateID)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let duplicates = try encoder.encode(ReturnArchive(items: [record, record]))
        XCTAssertThrowsError(try ArchiveCodec.decode(duplicates))

        var future = ReturnArchive(items: [record])
        future.version = 2
        XCTAssertThrowsError(try ArchiveCodec.decode(encoder.encode(future))) { error in
            XCTAssertEqual(error as? ReturnQueueError, .unsupportedArchiveVersion(2))
        }
        var invalid = record
        invalid.amountCents = Int.max
        let invalidData = try encoder.encode(ReturnArchive(items: [invalid]))
        XCTAssertThrowsError(try ArchiveCodec.decode(invalidData))
        XCTAssertThrowsError(try ArchiveCodec.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try ArchiveCodec.decode(Data("{}".utf8)))
    }

    func testPersistenceRoundTripAndMissingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ReturnRepository(fileURL: directory.appendingPathComponent("nested/returns.json"))
        XCTAssertEqual(try repository.load(), [])
        let records = [item(), item()]
        try repository.save(records)
        XCTAssertEqual(try repository.load(), records)
        try repository.save([])
        XCTAssertEqual(try repository.load(), [])
    }

    func testCorruptLoadDoesNotOverwriteExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ReturnRepository(fileURL: directory.appendingPathComponent("returns.json"))
        try repository.save([item()])
        let corrupt = Data("{ broken backup".utf8)
        try corrupt.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
    }

    func testInvalidSavePreservesLastValidData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ReturnRepository(fileURL: directory.appendingPathComponent("returns.json"))
        let saved = item()
        try repository.save([saved])
        let prior = try Data(contentsOf: repository.fileURL)
        var invalid = saved
        invalid.refundReceivedCents = -1
        XCTAssertThrowsError(try repository.save([invalid]))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), prior)
        XCTAssertEqual(try repository.load(), [saved])
    }
}
