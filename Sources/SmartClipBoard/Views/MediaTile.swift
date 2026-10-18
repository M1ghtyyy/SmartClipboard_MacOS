import SwiftUI

/// Rounded thumbnail of a copied photo, GIF or video with a small type badge.
struct MediaTile: View {
    let item: ClipItem
    let thumbnail: NSImage?
    let isCopied: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onRemove: () -> Void
    let onDragChange: (Bool) -> Void

    private static let side: CGFloat = 64
    private static let corner = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            preview
                .frame(width: Self.side, height: Self.side)
                .clipped()

            badge.padding(4)

            if isCopied {
                ZStack {
                    Color.black.opacity(0.55)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(Self.corner)
        .overlay(Self.corner.strokeBorder(Color.white.opacity(isHovered ? 0.45 : 0.12), lineWidth: 1))
        .scaleEffect(isHovered ? 1.05 : 1)
        .overlay(DragSource(
            payload: { (item.mediaURL ?? URL(fileURLWithPath: "/")) as NSURL },
            dragImage: { DragImages.tile(thumbnail) },
            onClick: onClick,
            onHover: onHover,
            onRemove: onRemove,
            onDragChange: onDragChange
        ))
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isCopied)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.white.opacity(0.08)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch item.mediaKind {
        case .gif:
            Text("GIF")
                .font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.65)))
                .foregroundStyle(.white)
        case .video:
            symbolBadge("video.fill")
        default:
            symbolBadge("photo")
        }
    }

    private func symbolBadge(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 14)
            .background(Capsule().fill(Color.black.opacity(0.65)))
    }
}
