import Foundation

public actor CreatorStore {
    private let fileURL: URL
    private var library: CreatorLibrary
    private var recoveryCopyMade = false
    public let recoveryMessage: String?
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { library = try decoder.decode(CreatorLibrary.self, from: Data(contentsOf: fileURL)); recoveryMessage = nil }
            catch { library = CreatorLibrary(); recoveryMessage = "Saved library could not be read; original data is preserved. Add new items to create a separate recovered library. \(error.localizedDescription)" }
        } else { library = CreatorLibrary(); recoveryMessage = nil }
    }

    public func all() -> [CreatorVideo] { library.videos }

    @discardableResult
    public func add(_ incoming: [CreatorVideo]) throws -> Int {
        var candidate = library
        var byIdentity = Dictionary(candidate.videos.map { ($0.identityKey, $0) }, uniquingKeysWith: { _, latest in latest })
        var ids = Set(candidate.videos.map(\.id))
        var added = 0
        for video in incoming where byIdentity[video.identityKey] == nil {
            var accepted = video
            if ids.contains(accepted.id) { repeat { accepted.id = UUID().uuidString } while ids.contains(accepted.id) }
            ids.insert(accepted.id)
            byIdentity[accepted.identityKey] = accepted
            added += 1
        }
        candidate.videos = byIdentity.values.sorted { $0.capturedAt > $1.capturedAt }
        try save(candidate)
        return added
    }

    public func updateWorkspace(id: String, workspace: String?) throws {
        guard let index = library.videos.firstIndex(where: { $0.id == id }) else { return }
        var candidate = library
        candidate.videos[index].workspace = workspace?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try save(candidate)
    }

    public func updateNotes(id: String, notes: String) throws {
        guard let index = library.videos.firstIndex(where: { $0.id == id }) else { return }
        var candidate = library
        candidate.videos[index].notes = notes
        try save(candidate)
    }

    public func delete(id: String) throws {
        var candidate = library
        candidate.videos.removeAll { $0.id == id }
        try save(candidate)
    }

    public func exportJSON(ids: Set<String>) throws -> Data {
        let exportEncoder = JSONEncoder()
        exportEncoder.dateEncodingStrategy = .iso8601
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try exportEncoder.encode(library.videos.filter { ids.contains($0.id) })
    }

    public func exportCSV(ids: Set<String>) -> Data {
        let rows = library.videos.filter { ids.contains($0.id) }
        let header = "title,channel,url,published_at,captured_at,source,views,likes,comments,workspace,notes"
        let body = rows.map { video in
            [video.title, video.channel, video.url, video.publishedAt.map(Self.timestamp) ?? "", Self.timestamp(video.capturedAt), video.source.rawValue, video.views.map(String.init) ?? "", video.likes.map(String.init) ?? "", video.comments.map(String.init) ?? "", video.workspace ?? "", video.notes].map(Self.csvField).joined(separator: ",")
        }
        return Data(([header] + body).joined(separator: "\r\n").data(using: .utf8) ?? Data())
    }

    private func save(_ candidate: CreatorLibrary) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if recoveryMessage != nil && !recoveryCopyMade {
            let backup = URL(fileURLWithPath: fileURL.path + ".\(UUID().uuidString).recovery")
            try FileManager.default.copyItem(at: fileURL, to: backup)
            recoveryCopyMade = true
        }
        let data = try encoder.encode(candidate)
        try data.write(to: fileURL, options: .atomic)
        library = candidate
    }
    private static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func csvField(_ value: String) -> String {
        let dangerous = value.unicodeScalars.first { !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
        let safeValue: String
        if let first = dangerous, ["=", "+", "-", "@"].contains(String(first)) { safeValue = "'" + value }
        else { safeValue = value }
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension String { fileprivate var nilIfEmpty: String? { isEmpty ? nil : self } }
