import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Private scratch folder for images that only existed on the clipboard (screenshots, "Copy Image").
enum TempStorage {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SmartClipBoard", isDirectory: true)

    static func reset() {
        wipe()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func newFileURL(extension ext: String) -> URL {
        directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}

/// In-memory clipboard history shown by the island.
final class ClipboardStore: ObservableObject {
    static let maxWords = 30
    static let maxMedia = 20

    @Published private(set) var words: [ClipItem] = []
    @Published private(set) var media: [ClipItem] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    @Published private(set) var lastCopiedID: UUID?
    @Published var isPaused = false
    @Published var accessDenied = false

    weak var monitor: ClipboardMonitor?

    /// Keeps the lazy TIFF provider alive while its pasteboard item is current.
    private var imageProvider: LazyImageProvider?

    // MARK: Adding

    func addText(_ text: String) {
        if let index = words.firstIndex(where: { $0.text == text }) {
            words.insert(words.remove(at: index), at: 0)
            return
        }
        words.insert(ClipItem(text: text), at: 0)
        if words.count > Self.maxWords {
            words.removeLast(words.count - Self.maxWords)
        }
    }

    func addMediaFiles(_ files: [(MediaKind, URL)]) {
        // Insert in reverse so the first selected file ends up first.
        for (kind, url) in files.reversed() {
            if let index = media.firstIndex(where: { $0.mediaURL == url }) {
                media.insert(media.remove(at: index), at: 0)
            } else {
                insertMedia(ClipItem(media: kind, url: url, ownsFile: false))
            }
        }
    }

    /// Saves clipboard-only image data to the temp folder off the main thread, then records it.
    func addImageData(_ data: Data, kind: MediaKind, needsPNGConversion: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var data = data
            if needsPNGConversion {
                guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return }
                data = png
            }
            let url = TempStorage.newFileURL(extension: kind == .gif ? "gif" : "png")
            do { try data.write(to: url) } catch { return }
            DispatchQueue.main.async {
                self?.insertMedia(ClipItem(media: kind, url: url, ownsFile: true))
            }
        }
    }

    private func insertMedia(_ item: ClipItem) {
        media.insert(item, at: 0)
        makeThumbnail(for: item)
        while media.count > Self.maxMedia {
            discard(media.removeLast())
        }
    }

    // MARK: Removing

    func remove(_ item: ClipItem) {
        words.removeAll { $0.id == item.id }
        if let index = media.firstIndex(where: { $0.id == item.id }) {
            discard(media.remove(at: index))
        }
    }

    func clearAll() {
        words.removeAll()
        media.forEach(discard)
        media.removeAll()
    }

    /// Drops media whose original file was moved or deleted since it was copied.
    func pruneMissingFiles() {
        let missing = media.filter { item in
            guard let url = item.mediaURL else { return false }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        missing.forEach(remove)
    }

    private func discard(_ item: ClipItem) {
        thumbnails[item.id] = nil
        if item.ownsFile, let url = item.mediaURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Copying back

    func copy(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        imageProvider = nil

        switch item.content {
        case .text(let text):
            pasteboardItem.setString(text, forType: .string)

        case .media(let kind, let url, _):
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            if kind != .video,
               let type = UTType(filenameExtension: url.pathExtension),
               let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                // The file's own bytes (PNG, JPEG, HEIC, GIF...) for apps that take image data.
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
                // Many apps only read TIFF; build it only if one actually asks for it.
                if kind == .photo, type != .png, type != .tiff {
                    let provider = LazyImageProvider(url: url)
                    pasteboardItem.setDataProvider(provider, forTypes: [.tiff])
                    imageProvider = provider
                }
            }
        }

        pasteboard.writeObjects([pasteboardItem])
        monitor?.syncChangeCount()

        lastCopiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if self.lastCopiedID == item.id { self.lastCopiedID = nil }
            self.promote(item)
        }
    }

    private func promote(_ item: ClipItem) {
        if let index = words.firstIndex(where: { $0.id == item.id }) {
            words.insert(words.remove(at: index), at: 0)
        } else if let index = media.firstIndex(where: { $0.id == item.id }) {
            media.insert(media.remove(at: index), at: 0)
        }
    }

    // MARK: Thumbnails

    private func makeThumbnail(for item: ClipItem) {
        guard let url = item.mediaURL else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 128, height: 128),
            scale: 2,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                guard let self, self.media.contains(where: { $0.id == item.id }) else { return }
                self.thumbnails[item.id] = image
            }
        }
    }
}

/// Supplies TIFF data for a copied photo only when the pasting app requests it.
private final class LazyImageProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = NSImage(contentsOf: url)?.tiffRepresentation {
            item.setData(data, forType: type)
        }
    }
}
