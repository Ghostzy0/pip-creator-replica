import CreatorCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct CreatorReplicaApp: App {
    @StateObject private var model = ReplicaModel()

    var body: some Scene {
        WindowGroup {
            ReplicaShell()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
                .task { await model.load() }
        }
    }
}

private enum ReplicaPage: String, CaseIterable, Identifiable {
    case home = "Home"
    case optimize = "Optimize"
    case chat = "Chat"
    case keywords = "Keywords"
    case outliers = "Outliers"
    case ideas = "Daily Ideas"
    case competitors = "Competitors"
    case subscribers = "Subscribers"
    case learn = "Learn"
    case create = "Create"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house"
        case .optimize: "sparkles.rectangle.stack"
        case .chat: "bubble.left.and.bubble.right"
        case .keywords: "magnifyingglass"
        case .outliers: "arrow.up.right.circle"
        case .ideas: "lightbulb"
        case .competitors: "person.2"
        case .subscribers: "person.3"
        case .learn: "book"
        case .create: "square.and.pencil"
        }
    }
}

private enum ReplicaExportFormat: String, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    var id: String { rawValue }
}

@MainActor private final class ReplicaModel: ObservableObject {
    @Published var page: ReplicaPage? = .home
    @Published var videos: [CreatorVideo] = []
    @Published var selectedID: String?
    @Published var search = ""
    @Published var notice: String?
    @Published var recoveryWarning: String?
    @Published var error: String?
    @Published var showingImporter = false
    @Published var showingManualNote = false
    @Published var exportFormat: ReplicaExportFormat?
    @Published var exportDocument: ReplicaExportDocument?
    @Published var showingExportPreview = false
    @Published var selectedExportIDs = Set<String>()
    var exportConfirmed = false
    private var exportItemCount = 0
    private let store: CreatorStore

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = CreatorStore(fileURL: root.appendingPathComponent("CreatorReplica", isDirectory: true).appendingPathComponent("library.json"))
    }

    var matches: [CreatorVideo] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return videos }
        return videos.filter { $0.title.localizedCaseInsensitiveContains(needle) || $0.channel.localizedCaseInsensitiveContains(needle) || $0.notes.localizedCaseInsensitiveContains(needle) }
    }

    var selected: CreatorVideo? { matches.first { $0.id == selectedID } ?? matches.first }

    func load() async {
        videos = await store.all()
        if recoveryWarning == nil { recoveryWarning = await store.recoveryMessage }
        if selectedID == nil { selectedID = videos.first?.id }
    }

    func addManual(title: String, channel: String, url: String, notes: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { error = "Add a title first."; return }
        do {
            let video = CreatorVideo(title: cleanTitle, channel: channel.trimmingCharacters(in: .whitespacesAndNewlines), url: url.trimmingCharacters(in: .whitespacesAndNewlines), source: .manual, notes: notes)
            _ = try await store.add([video])
            await load(); selectedID = video.id; notice = "Saved a local research note."; error = nil
        } catch let issue { error = issue.localizedDescription }
    }

    func importFile(_ url: URL) async {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > CreatorImporter.maxFileBytes { throw CreatorImportError.tooLarge }
            let rows = try CreatorImporter.decode(data: Data(contentsOf: url, options: .mappedIfSafe), filename: url.lastPathComponent)
            let count = try await store.add(rows)
            await load()
            notice = "Added \(count) local research records."
            error = nil
        } catch let issue { error = issue.localizedDescription; notice = nil }
    }

    func prepareExport(format: ReplicaExportFormat) {
        selectedExportIDs = Set(videos.map(\.id))
        exportConfirmed = false
        exportFormat = format
        notice = nil
        error = nil
        showingExportPreview = true
    }

    func exportPreviewDidDismiss() {
        if exportConfirmed {
            exportConfirmed = false
            beginExport()
        } else if exportDocument == nil {
            exportFormat = nil
        }
    }

    private func beginExport() {
        guard let format = exportFormat, !selectedExportIDs.isEmpty else { return }
        let ids = selectedExportIDs
        exportItemCount = ids.count
        showingExportPreview = false
        Task {
            do {
                let data = format == .json
                    ? try await store.exportJSON(ids: ids)
                    : await store.exportCSV(ids: ids)
                exportDocument = ReplicaExportDocument(data: data)
            } catch {
                self.error = error.localizedDescription
                exportFormat = nil
            }
        }
    }

    func finishedExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            notice = "Exported \(exportItemCount) selected item\(exportItemCount == 1 ? "" : "s")."
            error = nil
        case .failure(let issue):
            if issue is CancellationError {
                notice = "Export canceled; no file was saved."
            } else {
                error = issue.localizedDescription
            }
        }
        exportFormat = nil
        exportDocument = nil
    }
}

private struct ReplicaShell: View {
    @EnvironmentObject private var model: ReplicaModel
    @State private var expandedMore = true
    private var accent: Color { Color.accentColor }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                topBar
                if let warning = model.recoveryWarning { Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(10).frame(maxWidth: .infinity, alignment: .leading) }
                if let error = model.error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).padding(10).frame(maxWidth: .infinity, alignment: .leading) }
                if let notice = model.notice { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading) }
                ScrollView { pageBody.padding(30).frame(maxWidth: 1120, alignment: .leading).frame(maxWidth: .infinity, alignment: .center) }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.commaSeparatedText, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await model.importFile(url) } }
            case .failure(let failure): model.error = failure.localizedDescription
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { model.exportDocument != nil },
                set: { if !$0 { model.exportFormat = nil; model.exportDocument = nil } }
            ),
            document: model.exportDocument ?? ReplicaExportDocument(data: Data()),
            contentType: model.exportFormat == .csv ? .commaSeparatedText : .json,
            defaultFilename: "creator-research"
        ) { result in
            model.finishedExport(result)
        }
        .sheet(isPresented: $model.showingManualNote) { ReplicaManualNoteSheet().environmentObject(model) }
        .sheet(isPresented: $model.showingExportPreview, onDismiss: { model.exportPreviewDidDismiss() }) {
            ReplicaExportPreview().environmentObject(model)
        }
    }

    private var sidebar: some View {
        List(selection: $model.page) {
            Section {
                pageLink(.home)
                pageLink(.optimize)
                pageLink(.chat)
            }
            Section("Research") {
                pageLink(.keywords)
                pageLink(.outliers)
            }
            Section {
                DisclosureGroup("More Tools", isExpanded: $expandedMore) {
                    pageLink(.ideas)
                    pageLink(.competitors)
                    pageLink(.subscribers)
                    pageLink(.learn)
                    pageLink(.create)
                }
            }
            Section {
            Label("Creator Baseline · Neutral Core", systemImage: "circle.grid.2x2.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Creator Baseline")
        .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 270)
    }

    private func pageLink(_ page: ReplicaPage) -> some View {
        Label(page.rawValue, systemImage: page.icon).tag(page)
    }

    private var topBar: some View {
        HStack {
            Text((model.page ?? .home).rawValue).font(.title2.weight(.semibold))
            Spacer()
            TextField("Search local research", text: $model.search)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            Menu {
                Button("Export as CSV") { model.prepareExport(format: .csv) }
                Button("Export as JSON") { model.prepareExport(format: .json) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered).disabled(model.videos.isEmpty)
            Button { model.showingManualNote = true } label: { Label("Add note", systemImage: "square.and.pencil") }.buttonStyle(.bordered)
            Button { model.showingImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .background(.bar)
    }

    @ViewBuilder private var pageBody: some View {
        switch model.page ?? .home {
        case .home: homePage
        case .optimize: localRecordsPage(title: "Optimize", subtitle: "Browse local records. Dedicated title, description and thumbnail review workflows are not implemented in this baseline.")
        case .chat: unavailablePage(title: "Chat", text: "No assistant is connected in this baseline. Your research stays on this Mac; no prompt or content is sent to a model.")
        case .keywords: keywordsPage
        case .outliers: localRecordsPage(title: "Outlier research", subtitle: "Browse raw values you supplied. This baseline does not compare channel performance, calculate outlier scores or fetch live metrics.")
        case .ideas: localRecordsPage(title: "Daily Ideas", subtitle: "Keep your own video ideas alongside their source notes. No predicted performance is generated.")
        case .competitors: localRecordsPage(title: "Competitors", subtitle: "Organize public links and notes you add yourself. No channels are monitored in the background.")
        case .subscribers: unavailablePage(title: "Subscribers", text: "Channel analytics are not connected. Import a permitted owner export or add a note manually; missing figures stay unknown.")
        case .learn: unavailablePage(title: "Learn", text: "Learning resources are not bundled in this offline baseline.")
        case .create: localRecordsPage(title: "Create", subtitle: "Browse local research records. Drafting and generation tools are not implemented in this baseline.")
        }
    }

    private var homePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock("Creator workspace", subtitle: "A local recreation of the documented creator-tool navigation, with offline research records.")
            HStack(spacing: 14) {
                metricCard("Research records", value: "\(model.videos.count)", detail: "Stored on this Mac", icon: "rectangle.stack")
                metricCard("Sources", value: "\(Set(model.videos.map(\.source)).count)", detail: "Recorded provenance types", icon: "link")
                metricCard("Connections", value: "0", detail: "No live services connected", icon: "bolt.slash")
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent research").font(.headline)
                    if model.matches.isEmpty { emptyPanel("Import a CSV/JSON file or save a manual research note to begin.") }
                    else { ForEach(model.matches.prefix(5)) { recordRow($0) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start here").font(.headline)
                    actionCard("Research keywords", text: "Search your own saved titles and notes.", page: .keywords)
                    actionCard("Browse research", text: "View your saved sources and raw fields.", page: .optimize)
                    actionCard("Track a competitor", text: "Store links and observations manually.", page: .competitors)
                }.frame(maxWidth: 300, alignment: .leading)
            }
        }
    }

    private var keywordsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock("Keyword research", subtitle: "Search your imported titles and notes. No search-volume or competition estimate is presented.")
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Enter a topic or phrase", text: $model.search).textFieldStyle(.plain) }
                .padding(13).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            Text("Local matches · \(model.matches.count)").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            if model.matches.isEmpty { emptyPanel("No local matches. Import a permitted research file to populate this view.") }
            else { ForEach(model.matches) { recordRow($0) } }
        }
    }

    private func localRecordsPage(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock(title, subtitle: subtitle)
            if model.matches.isEmpty { emptyPanel("No local records yet. Import a file to begin.") }
            else {
                ForEach(model.matches) { record in
                    VStack(alignment: .leading, spacing: 10) {
                        recordRow(record)
                        HStack(spacing: 18) {
                            dataValue("Views", record.views.map(String.init) ?? "Unknown")
                            dataValue("Likes", record.likes.map(String.init) ?? "Unknown")
                            dataValue("Comments", record.comments.map(String.init) ?? "Unknown")
                            Spacer()
                            Text(record.source.rawValue).font(.caption).foregroundStyle(.secondary)
                        }.padding(.leading, 38)
                    }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }
        }
    }

    private func unavailablePage(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock(title, subtitle: text)
            emptyPanel("This capability is not active in the local baseline.")
        }
    }

    private func titleBlock(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricCard(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }

    private func actionCard(_ title: String, text: String, page: ReplicaPage) -> some View {
        Button { model.page = page } label: {
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.subheadline.weight(.semibold)); Text(text).font(.caption).foregroundStyle(.secondary); Label("Open", systemImage: "arrow.right").font(.caption.weight(.medium)).padding(.top, 3) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
        }.buttonStyle(.plain)
    }

    private func emptyPanel(_ text: String) -> some View {
        ContentUnavailableView { Label("Nothing here yet", systemImage: "tray") } description: { Text(text) }
            .padding(18).frame(maxWidth: .infinity, minHeight: 210).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func recordRow(_ record: CreatorVideo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "play.rectangle").font(.title3).foregroundStyle(accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.subheadline.weight(.semibold))
                Text(record.channel.isEmpty ? "Channel unknown" : record.channel).font(.caption).foregroundStyle(.secondary)
                if !record.notes.isEmpty { Text(record.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Text(record.source.rawValue).font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }

    private func dataValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.monospacedDigit()) }
    }
}

private struct ReplicaManualNoteSheet: View {
    @EnvironmentObject private var model: ReplicaModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var channel = ""
    @State private var url = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New research note").font(.title2.weight(.semibold))
            TextField("Video or topic title", text: $title)
            TextField("Channel (optional)", text: $channel)
            TextField("Source URL (optional)", text: $url)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...7)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save note") {
                    Task { await model.addManual(title: title, channel: channel, url: url, notes: notes); if model.error == nil { dismiss() } }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 460)
    }
}

private struct ReplicaExportPreview: View {
    @EnvironmentObject private var model: ReplicaModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Export research").font(.title2.weight(.semibold))
            Text("Choose which items to include as \(model.exportFormat?.rawValue ?? "data"). This app does not upload exports. Choose where to save the file.")
                .font(.callout).foregroundStyle(.secondary)
            Text("\(model.selectedExportIDs.count) of \(model.videos.count) items selected")
                .font(.caption.weight(.medium))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.videos) { video in
                        Toggle(isOn: Binding(
                            get: { model.selectedExportIDs.contains(video.id) },
                            set: { checked in
                                if checked { model.selectedExportIDs.insert(video.id) }
                                else { model.selectedExportIDs.remove(video.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.title).font(.callout.weight(.medium))
                                Text("\(video.channel.isEmpty ? "No channel" : video.channel) · \(video.source.rawValue)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox).padding(.vertical, 3)
                    }
                }
            }.frame(maxHeight: 310)
            Text("Fields: id, title, channel, url, published_at, captured_at, source, views, likes, comments, workspace, notes.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Select all") { model.selectedExportIDs = Set(model.videos.map(\.id)) }
                Button("Select none") { model.selectedExportIDs.removeAll() }
                Spacer()
                Button("Cancel") { model.exportConfirmed = false; model.exportFormat = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose save location…") { model.exportConfirmed = true; dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(model.selectedExportIDs.isEmpty)
            }
        }
        .padding(22).frame(width: 520, height: 480)
    }
}

private struct ReplicaExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
