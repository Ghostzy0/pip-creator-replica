import Foundation
import CoreFoundation


public enum ResearchSource: String, Codable, CaseIterable, Sendable {
    case manual = "Manual"
    case userFile = "User supplied file"
    case sample = "Sample"
    case officialYouTube = "YouTube Data API"
    case ownerAnalytics = "YouTube Analytics"
}

public struct CreatorVideo: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var channel: String
    public var url: String
    public var publishedAt: Date?
    public var capturedAt: Date
    public var source: ResearchSource
    public var views: Int64?
    public var likes: Int64?
    public var comments: Int64?
    public var notes: String
    public var workspace: String?

    public init(id: String = UUID().uuidString, title: String, channel: String = "", url: String = "", publishedAt: Date? = nil, capturedAt: Date = .now, source: ResearchSource = .manual, views: Int64? = nil, likes: Int64? = nil, comments: Int64? = nil, notes: String = "", workspace: String? = nil) {
        self.id = id
        self.title = title
        self.channel = channel
        self.url = url
        self.publishedAt = publishedAt
        self.capturedAt = capturedAt
        self.source = source
        self.views = views
        self.likes = likes
        self.comments = comments
        self.notes = notes
        self.workspace = workspace
    }

    public var identityKey: String {
        if !url.isEmpty { return url.lowercased() }
        return "\(channel.lowercased())|\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

public struct CreatorLibrary: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var videos: [CreatorVideo]
    public init(schemaVersion: Int = 1, videos: [CreatorVideo] = []) {
        self.schemaVersion = schemaVersion
        self.videos = videos
    }
}

public enum CreatorImportError: Error, LocalizedError, Equatable {
    case tooLarge
    case unsupportedFormat
    case missingTitle
    case invalidJSON(String)
    case invalidCSV(String)
    case invalidMetric(String)
    case disallowedProvenance
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "This file is larger than 25 MB."
        case .unsupportedFormat: "Choose a CSV or JSON file."
        case .missingTitle: "No usable video titles were found. Include a title column."
        case .invalidJSON(let reason): "Could not read the JSON file: \(reason)"
        case .invalidCSV(let reason): "Could not read the CSV file: \(reason)"
        case .invalidMetric(let field): "The \(field) field contains a value that is not a whole-number count. Correct it or leave it blank."
        case .disallowedProvenance: "This file declares YouTube API data. API data cannot be imported through the manual-file path in this version."
        case .unreadable(let reason): "Could not read this file: \(reason)"
        }
    }
}

public enum CreatorImporter {
    public static let maxFileBytes = 25 * 1024 * 1024

    public static func decode(data: Data, filename: String, now: Date = .now) throws -> [CreatorVideo] {
        guard data.count <= maxFileBytes else { throw CreatorImportError.tooLarge }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let rows: [[String: String]]
        switch ext {
        case "csv": rows = try parseCSV(data: data)
        case "json": rows = try parseJSON(data: data)
        default: throw CreatorImportError.unsupportedFormat
        }
        var results: [CreatorVideo] = []
        for row in rows {
            let normalized = Dictionary(row.map { (normalize($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
            let declaredOrigins = ["source", "provenance"].compactMap { value(normalized, [$0]).map(normalize) }
            if declaredOrigins.contains(where: { origin in
                ["youtubedataapi", "youtubeanalytics", "owneranalytics", "officialyoutube"].contains(where: origin.contains)
            }) {
                throw CreatorImportError.disallowedProvenance
            }
            guard let title = value(normalized, ["title", "videotitle", "name"]), !title.isEmpty else { continue }
            let views = try metric(normalized, keys: ["views", "viewcount"], label: "views")
            let likes = try metric(normalized, keys: ["likes", "likecount"], label: "likes")
            let comments = try metric(normalized, keys: ["comments", "commentcount"], label: "comments")
            let url = value(normalized, ["url", "videourl", "link"]) ?? ""
            let videoID = value(normalized, ["videoid", "id"]) ?? ""
            let channel = value(normalized, ["channel", "channelname", "creator"]) ?? ""
            let dateText = value(normalized, ["publishedat", "published", "date"])
            let capturedText = value(normalized, ["capturedat", "importedat"])
            let sourceText = value(normalized, ["source", "provenance"]).map(normalize)
            results.append(CreatorVideo(
                id: videoID.isEmpty ? UUID().uuidString : videoID,
                title: title,
                channel: channel,
                url: url,
                publishedAt: dateText.flatMap(parseDate),
                capturedAt: capturedText.flatMap(parseDate) ?? now,
                source: sourceText == "sample" ? .sample : .userFile,
                views: views,
                likes: likes,
                comments: comments,
                notes: value(normalized, ["notes", "researchnotes", "description"]) ?? "",
                workspace: value(normalized, ["workspace", "project"])
            ))
        }
        guard !results.isEmpty else { throw CreatorImportError.missingTitle }
        return results
    }

    private static func parseJSON(data: Data) throws -> [[String: String]] {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw CreatorImportError.invalidJSON(error.localizedDescription) }
        guard let values = object as? [[String: Any]] else {
            throw CreatorImportError.invalidJSON("Expected an array of video objects.")
        }
        return values.map { row in
            row.reduce(into: [String: String]()) { result, pair in
                switch pair.value {
                case is NSNull: break
                case let value as String: result[pair.key] = value
                case let value as NSNumber:
                    if CFGetTypeID(value) == CFBooleanGetTypeID() { break }
                    result[pair.key] = value.stringValue
                default: break
                }
            }
        }
    }

    private static func parseCSV(data: Data) throws -> [[String: String]] {
        guard var text = String(data: data, encoding: .utf8) else { throw CreatorImportError.invalidCSV("The file must use UTF-8 encoding.") }
        if text.first == "\u{feff}" { text.removeFirst() }
        var records: [[String]] = []
        var record: [String] = []
        var field: [UInt8] = []
        var quoted = false
        let bytes = Array(text.utf8)
        var i = 0
        func fieldString(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
        while i < bytes.count {
            let byte = bytes[i]
            if quoted {
                if byte == 34 {
                    if i + 1 < bytes.count && bytes[i + 1] == 34 { field.append(34); i += 2 }
                    else { quoted = false; i += 1 }
                } else { field.append(byte); i += 1 }
                continue
            }
            switch byte {
            case 34 where field.isEmpty:
                quoted = true; i += 1
            case 44:
                record.append(fieldString(field)); field = []; i += 1
            case 10, 13:
                record.append(fieldString(field)); records.append(record); record = []; field = []
                if byte == 13 && i + 1 < bytes.count && bytes[i + 1] == 10 { i += 2 } else { i += 1 }
            default:
                field.append(byte); i += 1
            }
        }
        if quoted { throw CreatorImportError.invalidCSV("A quoted field was not closed.") }
        if !field.isEmpty || !record.isEmpty { record.append(fieldString(field)); records.append(record) }
        guard let headerRow = records.first else { throw CreatorImportError.missingTitle }
        let headers = headerRow.map(normalize)
        guard Set(headers).count == headers.count else { throw CreatorImportError.invalidCSV("Column names repeat after spaces and punctuation are removed. Rename the duplicate columns and retry.") }
        guard headers.contains("title") || headers.contains("videotitle") || headers.contains("name") else { throw CreatorImportError.missingTitle }
        return records.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { values in
            Dictionary(uniqueKeysWithValues: headers.enumerated().compactMap { index, header in
                index < values.count ? (header, values[index].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            })
        }
    }

    private static func normalize(_ key: String) -> String {
        String(key.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    private static func value(_ row: [String: String], _ keys: [String]) -> String? {
        for key in keys { if let result = row[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty { return result } }
        return nil
    }
    private static func metric(_ row: [String: String], keys: [String], label: String) throws -> Int64? {
        guard let raw = value(row, keys) else { return nil }
        guard let parsed = parseInteger(raw) else { throw CreatorImportError.invalidMetric(label) }
        return parsed
    }
    private static func parseInteger(_ string: String) -> Int64? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let groups = value.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        if groups.count > 1 && (groups[0].count > 3 || groups[0].count == 0 || groups.dropFirst().contains(where: { $0.count != 3 })) { return nil }
        return Int64(groups.joined())
    }
    private static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        // Prior Creator JSON exports used JSONEncoder's reference-date numeric form.
        if let referenceInterval = Double(string), referenceInterval.isFinite, abs(referenceInterval) < 4_000_000_000,
           string.contains(".") || string.count >= 9 {
            return Date(timeIntervalSinceReferenceDate: referenceInterval)
        }
        for format in ["yyyy-MM-dd", "M/d/yyyy", "d/M/yyyy"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_GB"); formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
