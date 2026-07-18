import Foundation
import Testing

@Suite("Transaction contract oracle")
struct TransactionContractTests {
    @Test("fixture inventory is nonempty before production implementation")
    func productionContractIsRequired() throws {
        let root = try repositoryRoot()
        let casesURL = root.appendingPathComponent("fixtures/transactions/1.0.0/rev-001/cases.json")
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: casesURL)) as? [String: Any]
        )
        let cases = try #require(object["cases"] as? [[String: Any]])
        #expect(cases.isEmpty == false)
        Issue.record("ReRoomTransactionCore production contract is intentionally absent during RED")
    }

    private func repositoryRoot() throws -> URL {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while cursor.path != "/" {
            if FileManager.default.fileExists(
                atPath: cursor.appendingPathComponent("docs/contracts/transaction.schema.json").path
            ) {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
