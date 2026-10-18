import SwiftUI

/// Capsule showing the first word of a copied text. Click copies it, drag drops the full text.
struct WordChip: View {
    let item: ClipItem
    let isCopied: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onRemove: () -> Void
    let onDragChange: (Bool) -> Void

    var body: some View {
        Text(item.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .opacity(isCopied ? 0 : 1)
            .overlay {
                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
            .background(Capsule().fill(Color.white.opacity(isHovered || isCopied ? 0.22 : 0.12)))
            .overlay(DragSource(
                payload: { (item.text ?? "") as NSString },
                dragImage: { DragImages.chip(item.label) },
                onClick: onClick,
                onHover: onHover,
                onRemove: onRemove,
                onDragChange: onDragChange
            ))
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.15), value: isCopied)
    }
}

/// Lays children out left to right, wrapping onto new rows like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
