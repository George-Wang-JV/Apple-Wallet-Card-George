import AppKit
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

struct SavedSkin: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let importedAt: Date
}

/// Owns image copies and per-device/card assignment history. Never writes to an iPhone.
@MainActor
final class SkinLibrary: ObservableObject {
    private struct Catalog: Codable {
        var skins: [SavedSkin] = []
        var histories: [String: [String]] = [:]
    }

    @Published private var catalog = Catalog()
    @Published private(set) var loadError: String?
    let directory: URL
    private let trashFile: (URL) throws -> Void

    init(directory: URL? = nil, trashFile: @escaping (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) {
        self.trashFile = trashFile
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // Keep the legacy data location across the Screen rename.
            .appendingPathComponent("AirCard/SkinLibrary", isDirectory: true)
        let index = self.directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do { catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: index)) }
            catch { loadError = "The skin library could not be read. Your files have been preserved. \(error.localizedDescription)" }
        }
    }

    var skins: [SavedSkin] { catalog.skins }

    func url(for skin: SavedSkin) -> URL {
        directory.appendingPathComponent(skin.id + ".png")
    }

    private func key(deviceID: String?, cardID: String) -> String {
        // Length-prefixed components avoid ambiguous pairs and separate offline records.
        let device = deviceID.map { "device:\($0)" } ?? "offline"
        let value = "\(device.utf8.count):\(device)\(cardID)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func history(deviceID: String?, cardID: String) -> [SavedSkin] {
        let byID = Dictionary(catalog.skins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (catalog.histories[key(deviceID: deviceID, cardID: cardID)] ?? []).compactMap { byID[$0] }
    }

    private func save(_ next: Catalog) throws {
        if let loadError { throw NSError(domain: "SkinLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: loadError]) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        catalog = next
    }

    @discardableResult
    func importImage(_ source: URL) throws -> SavedSkin {
        if let loadError { throw NSError(domain: "SkinLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: loadError]) }
        // Library selections already have stable PNG bytes; preserve their identity.
        if let existing = skins.first(where: { url(for: $0).standardizedFileURL == source.standardizedFileURL }),
           NSImage(contentsOf: source) != nil { return existing }
        guard let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SkinLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: "This image could not be opened. Choose a valid image file."])
        }
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let skin = skins.first(where: { $0.id == id }) ?? SavedSkin(id: id, name: source.deletingPathExtension().lastPathComponent, importedAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: skin), options: .atomic)
        var next = catalog
        if !next.skins.contains(where: { $0.id == id }) { next.skins.insert(skin, at: 0) }
        try save(next)
        return skin
    }

    func record(_ skin: SavedSkin, deviceID: String?, cardID: String) throws {
        var next = catalog
        let historyKey = key(deviceID: deviceID, cardID: cardID)
        var ids = next.histories[historyKey] ?? []
        ids.removeAll { $0 == skin.id }
        ids.insert(skin.id, at: 0)
        next.histories[historyKey] = ids
        try save(next)
    }

    func remove(_ skin: SavedSkin, protectedURLs: Set<URL>) throws {
        let imageURL = url(for: skin)
        guard !protectedURLs.contains(imageURL.standardizedFileURL) else {
            throw NSError(domain: "SkinLibrary", code: 3, userInfo: [NSLocalizedDescriptionKey: "This skin is used by a saved card. Change or clear that card's skin before deleting it."])
        }
        let previous = catalog
        var next = catalog
        next.skins.removeAll { $0.id == skin.id }
        next.histories = next.histories.mapValues { $0.filter { $0 != skin.id } }
        try save(next)
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) { try trashFile(imageURL) }
        } catch {
            try save(previous)
            throw error
        }
    }
}

struct SkinBrowserRequest: Identifiable {
    let id = UUID()
    var cardID: String?
    var deviceID: String?
    var historyOnly = false
}

struct SkinLibrarySheet: View {
    @ObservedObject var library: SkinLibrary
    let request: SkinBrowserRequest
    let currentURL: URL?
    let protectedURLs: Set<URL>
    let onSelect: (SavedSkin) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var historyOnly: Bool
    @State private var errorMessage: String?
    @State private var isEditing = false
    @State private var pendingDelete: SavedSkin?

    init(library: SkinLibrary, request: SkinBrowserRequest, currentURL: URL?, protectedURLs: Set<URL> = [], onSelect: @escaping (SavedSkin) -> Bool) {
        self.library = library
        self.request = request
        self.currentURL = currentURL
        self.protectedURLs = protectedURLs
        self.onSelect = onSelect
        _historyOnly = State(initialValue: request.historyOnly)
    }

    private var displayedSkins: [SavedSkin] {
        if historyOnly, let cardID = request.cardID {
            return library.history(deviceID: request.deviceID, cardID: cardID)
        }
        return library.skins
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(historyOnly ? "Skin History" : "Skin Library").font(.title2.bold())
                    Text(request.cardID == nil ? "Import once, reuse on any card. Images stay on this Mac." : "Choose a skin to preview. Click Flash Skins afterwards to apply it to your iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Button(action: importImages) { Label("Import Images…", systemImage: "plus") }
                    .disabled(library.loadError != nil)
                if request.cardID != nil {
                    Picker("Show", selection: $historyOnly) {
                        Text("All Skins").tag(false)
                        Text("Skin History").tag(true)
                    }.pickerStyle(.segmented).frame(width: 260)
                }
                Spacer()
                Button(isEditing ? "Finish Editing" : "Edit") { isEditing.toggle() }
                    .disabled(library.loadError != nil || library.skins.isEmpty)
                Text("\(displayedSkins.count) skins").foregroundStyle(.secondary)
            }
            if let message = errorMessage ?? library.loadError {
                Text(message).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            ScrollView {
                if displayedSkins.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: historyOnly ? "clock.arrow.circlepath" : "photo.on.rectangle.angled").font(.system(size: 38))
                        Text(historyOnly ? "No skin history yet" : "Your library is empty").font(.headline)
                        Text(historyOnly ? "Skins assigned to this card will appear here." : "Import images to keep reusable copies in your library.")
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 16) {
                        ForEach(displayedSkins) { skin in
                            skinTile(skin)
                        }
                    }.padding(4)
                }
            }
        }
        .padding(24)
        .frame(width: 720, height: 540)
        .alert("Delete skin?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Move to Trash", role: .destructive) {
                guard let skin = pendingDelete else { return }
                do {
                    try library.remove(skin, protectedURLs: protectedURLs)
                    errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
                pendingDelete = nil
            }
        } message: {
            Text("This removes the skin from your library and all skin histories, and moves its image to the Mac's Trash. Your original imported file and iPhone are unchanged.")
        }
    }

    private func skinTile(_ skin: SavedSkin) -> some View {
        let url = library.url(for: skin)
        let image = NSImage(contentsOf: url)
        let isCurrent = url == currentURL
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.15)).overlay(Text("Image unavailable"))
                }
            }
            .frame(height: 122).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(skin.name).font(.callout.weight(.medium)).lineLimit(1).help(skin.name)
            if isEditing {
                let inUse = protectedURLs.contains(url.standardizedFileURL)
                Button(role: .destructive) { pendingDelete = skin } label: {
                    Label(inUse ? "In Use" : "Delete", systemImage: "trash")
                }
                .disabled(inUse)
                .help(inUse ? "Change or clear the skin on every saved card using it before deleting." : "Remove from library and history")
            } else if request.cardID != nil {
                Button(isCurrent ? "Current Skin" : "Use Skin") {
                    if onSelect(skin) { dismiss() }
                    else { errorMessage = "Could not assign this skin. The device or card may have changed; close this window and try again." }
                }.disabled(image == nil || isCurrent).buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func importImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Save reusable copies in your local skin library."
        guard panel.runModal() == .OK else { return }
        var failures: [String] = []
        for url in panel.urls {
            do { try library.importImage(url) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        historyOnly = false
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}
