import Foundation
import UniformTypeIdentifiers

enum MediaKind {
    case photo, gif, video

    /// Classifies a file by its content type; returns nil for anything that isn't a photo, GIF or video.
    init?(fileURL: URL) {
        let type = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: fileURL.pathExtension)
        guard let type else { return nil }
        if type.conforms(to: .gif) {
            self = .gif
        } else if type.conforms(to: .image) {
            self = .photo
        } else if type.conforms(to: .movie) {
            self = .video
        } else {
            return nil
        }
    }
}

struct ClipItem: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        /// `ownsFile` is true when the file lives in our temp folder and must be deleted with the item.
        case media(MediaKind, URL, ownsFile: Bool)
    }

    let id = UUID()
    let content: Content
    /// Short label shown on the chip: the first word, with "…" when there is more.
    let label: String
    /// One-line preview of the full text (or the file name for media).
    let preview: String

    init(text: String) {
        content = .text(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = String(trimmed.prefix(while: { !$0.isWhitespace }))
        if firstWord.count > 14 {
            label = String(firstWord.prefix(13)) + "…"
        } else {
            label = firstWord.count < trimmed.count ? firstWord + "…" : firstWord
        }
        preview = String(trimmed.prefix(300))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    init(media kind: MediaKind, url: URL, ownsFile: Bool) {
        content = .media(kind, url, ownsFile: ownsFile)
        label = url.lastPathComponent
        preview = ownsFile ? "Copied image" : url.lastPathComponent
    }

    var text: String? {
        if case .text(let text) = content { return text }
        return nil
    }

    var mediaURL: URL? {
        if case .media(_, let url, _) = content { return url }
        return nil
    }

    var mediaKind: MediaKind? {
        if case .media(let kind, _, _) = content { return kind }
        return nil
    }

    var ownsFile: Bool {
        if case .media(_, _, let owns) = content { return owns }
        return false
    }
}
