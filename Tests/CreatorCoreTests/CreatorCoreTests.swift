import Foundation
import Testing
@testable import CreatorCore

struct CreatorCoreTests {
    @Test func parsesQuotedMultilineCSVAndKeepsUnknownDistinctFromZero() throws {
        let data = Data("title,channel,url,published_at,views,likes,comments\r\n\"A, quiet \"\"idea\"\"\nfor Sunday\",Maker,https://example.com/v,2026-10-01,0,,7\r\n".utf8)
        let rows = try CreatorImporter.decode(data: data, filename: "research.csv", now: Date(timeIntervalSince1970: 100))
        #expect(rows.count == 1)
        #expect(rows[0].title == "A, quiet \"idea\"\nfor Sunday")
        #expect(rows[0].views == 0)
        #expect(rows[0].likes == nil)
        #expect(rows[0].comments == 7)
        #expect(rows[0].source == .userFile)
    }

    @Test func parsesTypedJSONAndRejectsWrongTopLevelSchema() throws {
        let data = Data("[{\"id\":\"v1\",\"title\":\"Build log\",\"views\":1200,\"likes\":null}]".utf8)
        let rows = try CreatorImporter.decode(data: data, filename: "items.json")
        #expect(rows.first?.id == "v1")
        #expect(rows.first?.views == 1200)
        #expect(rows.first?.likes == nil)
        #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: Data("{\"title\":\"wrong shape\"}".utf8), filename: "bad.json") }
    }

    @Test func rejectsUnclosedCSVAndOversizedInputs() {
        #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: Data("title\n\"unfinished".utf8), filename: "bad.csv") }
        #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: Data(repeating: 0, count: CreatorImporter.maxFileBytes + 1), filename: "big.json") }
    }

    @Test func storeDeduplicatesPersistsAndExportsQuotedCSV() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.json")
        let store = CreatorStore(fileURL: file)
        let first = CreatorVideo(id: "1", title: "A, title", url: "https://example.com/a", source: .manual, views: 0)
        let duplicate = CreatorVideo(id: "2", title: "Changed title", url: "https://example.com/a", source: .userFile)
        #expect(try await store.add([first, duplicate]) == 1)
        let restored = CreatorStore(fileURL: file)
        #expect(await restored.all().count == 1)
        #expect(await restored.all().first?.views == 0)
        let csv = await restored.exportCSV(ids: ["1"])
        #expect(String(decoding: csv, as: UTF8.self).contains("\"A, title\""))
        let emptyExport = try await restored.exportJSON(ids: ["missing"])
        let emptyRows = try JSONDecoder().decode([CreatorVideo].self, from: emptyExport)
        #expect(emptyRows.isEmpty)
    }

    @Test func CSVAndJSONExportsRoundTripNotesDatesAndSampleProvenance() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CreatorStore(fileURL: folder.appendingPathComponent("library.json"))
        let published = Date(timeIntervalSince1970: 1_800_000_000)
        let captured = Date(timeIntervalSince1970: 1_800_000_100)
        let source = CreatorVideo(id: "sample-1", title: "Sample research", channel: "Example", url: "https://example.com/video", publishedAt: published, capturedAt: captured, source: .sample, views: 12, likes: 3, comments: 1, notes: "A useful note", workspace: "Series")
        _ = try await store.add([source])

        let json = try await store.exportJSON(ids: [source.id])
        let importedJSON = try CreatorImporter.decode(data: json, filename: "export.json", now: .distantPast).first
        #expect(importedJSON?.publishedAt == published)
        #expect(importedJSON?.capturedAt == captured)
        #expect(importedJSON?.source == .sample)
        #expect(importedJSON?.notes == "A useful note")
        #expect(importedJSON?.workspace == "Series")

        let csv = await store.exportCSV(ids: [source.id])
        let importedCSV = try CreatorImporter.decode(data: csv, filename: "export.csv", now: .distantPast).first
        #expect(importedCSV?.publishedAt == published)
        #expect(importedCSV?.capturedAt == captured)
        #expect(importedCSV?.source == .sample)
        #expect(importedCSV?.notes == "A useful note")
        #expect(importedCSV?.workspace == "Series")
    }

    @Test func rejectsDuplicateNormalizedHeadersAndMalformedMetrics() {
        let duplicate = Data("title,Title\na,b\n".utf8)
        #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: duplicate, filename: "duplicate.csv") }
        for metric in ["1.5", "1e6", "12x3", "1,23"] {
            let csv = Data("title,views\nvideo,\"\(metric)\"\n".utf8)
            #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: csv, filename: "metric.csv") }
        }
        let valid = try? CreatorImporter.decode(data: Data("title,views\nvideo,\"1,234\"\n".utf8), filename: "metric.csv")
        #expect(valid?.first?.views == 1234)
    }

    @Test func rejectsDeclaredYouTubeAPISourceOnManualImport() {
        let data = Data("[{\"title\":\"API item\",\"views\":12,\"source\":\"YouTube Data API\"}]".utf8)
        #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: data, filename: "api-export.json") }
    }

    @Test func rejectsAPIProvenanceEvenWhenOtherExportFieldsArePresent() {
        let data = Data("[{\"id\":\"v1\",\"title\":\"API item\",\"views\":12,\"capturedAt\":\"2026-10-23T00:00:00Z\",\"notes\":\"note\",\"source\":\"YouTube Analytics\"}]".utf8)
        #expect(throws: CreatorImportError.self) { try CreatorImporter.decode(data: data, filename: "api-export.json") }
    }

    @Test func storeRepairsDuplicateIDsAndCSVExportNeutralizesFormulaCells() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CreatorStore(fileURL: folder.appendingPathComponent("library.json"))
        _ = try await store.add([
            CreatorVideo(id: "same", title: "=HYPERLINK(\"https://bad.example\")", url: "https://example.com/first", notes: "\t@SUM(1,2)"),
            CreatorVideo(id: "same", title: "Second", url: "https://example.com/second")
        ])
        let rows = await store.all()
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
        let csv = String(decoding: await store.exportCSV(ids: Set(rows.map(\.id))), as: UTF8.self)
        #expect(csv.contains("\"'=HYPERLINK("))
        #expect(csv.contains("\"'\t@SUM"))
    }

    @Test func workspaceAssignmentPersistsAndOlderRecordsDecodeWithoutIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.json")
        let store = CreatorStore(fileURL: file)
        _ = try await store.add([CreatorVideo(id: "idea", title: "Idea")])
        try await store.updateWorkspace(id: "idea", workspace: "Autumn series")
        let reopened = CreatorStore(fileURL: file)
        #expect(await reopened.all().first?.workspace == "Autumn series")
        try await reopened.updateWorkspace(id: "idea", workspace: "  ")
        #expect(await reopened.all().first?.workspace == nil)
    }

    @Test func corruptLibraryIsPreservedDuringRecovery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = Data("not valid library".utf8)
        try original.write(to: file)
        let store = CreatorStore(fileURL: file)
        #expect(await store.all().isEmpty)
        #expect(await store.recoveryMessage != nil)
        _ = try await store.add([CreatorVideo(title: "New item")])
        let backup = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasSuffix(".recovery") }
        guard let backup else { Issue.record("recovery backup was not created"); return }
        #expect(try Data(contentsOf: backup) == original)
        #expect(await CreatorStore(fileURL: file).all().count == 1)
    }

    @Test func failedSaveDoesNotLeakMutationIntoLaterSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appendingPathComponent("not-a-directory")
        try Data("block writes".utf8).write(to: blocker)
        let store = CreatorStore(fileURL: blocker.appendingPathComponent("library.json"))
        do {
            _ = try await store.add([CreatorVideo(id: "rejected", title: "Rejected")])
            Issue.record("the write should have failed")
        } catch { }
        #expect(await store.all().isEmpty)

        try FileManager.default.removeItem(at: blocker)
        _ = try await store.add([CreatorVideo(id: "accepted", title: "Accepted")])
        #expect(await store.all().map(\.id) == ["accepted"])
        #expect(await CreatorStore(fileURL: blocker.appendingPathComponent("library.json")).all().map(\.id) == ["accepted"])
    }
}
