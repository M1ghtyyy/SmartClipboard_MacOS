import AppKit
import SwiftUI

/// Transparent AppKit overlay that turns a chip or tile into a click target and a drag source.
///
/// AppKit (rather than SwiftUI's `onDrag`) is used because it reports when the drag ends,
/// which keeps the island open for the whole drag, and because it handles hover and clicks
/// reliably in a panel that never becomes key.
struct DragSource: NSViewRepresentable {
    let payload: () -> NSPasteboardWriting
    let dragImage: () -> NSImage
    let onClick: () -> Void
    let onHover: (Bool) -> Void
    let onRemove: () -> Void
    let onDragChange: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView(frame: .zero)
        view.source = self
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.source = self
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var source: DragSource?
    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // If the item disappears mid-drag, don't leave the island stuck open.
        if window == nil, isDragging {
            isDragging = false
            source?.onDragChange(false)
        }
    }

    // MARK: Hover and click

    override func mouseEntered(with event: NSEvent) { source?.onHover(true) }
    override func mouseExited(with event: NSEvent) { source?.onHover(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil { source?.onClick() }
        mouseDownEvent = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let remove = NSMenuItem(title: "Remove", action: #selector(removeItem), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    @objc private func removeItem() {
        source?.onRemove()
    }

    // MARK: Drag

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, !isDragging, let source else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }

        mouseDownEvent = nil
        isDragging = true
        source.onDragChange(true)

        let image = source.dragImage()
        let point = convert(start, from: nil)
        let item = NSDraggingItem(pasteboardWriter: source.payload())
        item.setDraggingFrame(
            NSRect(
                x: point.x - image.size.width / 2,
                y: point.y - image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ),
            contents: image
        )
        beginDraggingSession(with: [item], event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        source?.onHover(false)
        source?.onDragChange(false)
    }
}

/// Images shown under the cursor while dragging.
enum DragImages {
    static func chip(_ label: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let size = NSSize(width: ceil(textSize.width) + 20, height: ceil(textSize.height) + 10)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.15, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            (label as NSString).draw(at: NSPoint(x: 10, y: 5), withAttributes: attributes)
            return true
        }
    }

    static func tile(_ thumbnail: NSImage?) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).addClip()
            guard let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 else {
                NSColor(white: 0.2, alpha: 1).setFill()
                rect.fill()
                return true
            }
            // Aspect-fill, like the tile itself.
            let scale = max(rect.width / thumbnail.size.width, rect.height / thumbnail.size.height)
            let width = thumbnail.size.width * scale
            let height = thumbnail.size.height * scale
            thumbnail.draw(in: NSRect(
                x: (rect.width - width) / 2,
                y: (rect.height - height) / 2,
                width: width,
                height: height
            ))
            return true
        }
    }
}
