import AppKit
import SwiftUI

/// Shared between the controller (which owns the window) and the SwiftUI view (which draws it).
final class IslandState: ObservableObject {
    @Published var isExpanded = false
    /// The notch is swelling slightly while the pointer rests on it, as a cue that it's about to open.
    @Published var isPeeking = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = true

    var expandedSize: CGSize {
        // Same odd/even width as the notch, so every island size centres on whole points.
        let width: CGFloat = notchSize.width.truncatingRemainder(dividingBy: 2) == 0 ? 520 : 521
        return CGSize(width: width, height: notchSize.height + 244)
    }

    var peekSize: CGSize {
        CGSize(width: notchSize.width + 2 * (IslandView.peekFlareRadius + 8), height: notchSize.height + 7)
    }
}

/// Where the notch is on the current setup.
struct NotchGeometry {
    let screen: NSScreen
    let size: CGSize
    /// Horizontal centre of the notch in screen coordinates.
    let centerX: CGFloat
    let hasNotch: Bool

    static func current() -> NotchGeometry? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = screen.frame.width - left - right
            if left > 0, right > 0, width > 0 {
                return NotchGeometry(
                    screen: screen,
                    size: CGSize(width: width, height: screen.safeAreaInsets.top),
                    centerX: screen.frame.minX + left + width / 2,
                    hasNotch: true
                )
            }
        }
        // No notch (lid closed on an external display): an invisible hover zone in the menu bar.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(
            screen: screen,
            size: CGSize(width: 200, height: menuBarHeight),
            centerX: screen.frame.midX,
            hasNotch: false
        )
    }
}

/// Borderless panel over the notch. It never becomes key or active, so the app you were
/// working in keeps keyboard focus and ⌘V lands there.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Receive mouse events over the whole frame, including transparent parts.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel's content view.
///
/// - Hover: event-driven detection for the whole panel, with no mouse polling and no
///   Accessibility permission.
/// - Layout: the SwiftUI view inside keeps one fixed size, centred on the notch. When the window
///   grows or shrinks around it, the content doesn't move on screen; the window only changes how
///   much of it is visible. If SwiftUI saw the size change, it would animate the shape from the
///   window's moving left edge and the shape would drift off-centre.
private final class IslandContainerView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

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

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        centerSubviews()
    }

    /// Centres each subview horizontally and pins it to the top edge.
    func centerSubviews() {
        for subview in subviews {
            subview.setFrameOrigin(NSPoint(
                x: ((bounds.width - subview.frame.width) / 2).rounded(),
                y: bounds.height - subview.frame.height
            ))
        }
    }
}

final class IslandController {
    let store: ClipboardStore
    let state = IslandState()

    private let panel = IslandPanel()
    private var container: IslandContainerView!
    private var hostingView: NSView!
    private var screenFrame: NSRect = .zero
    private var centerX: CGFloat = 0
    private var isDragging = false
    private var isClosing = false
    private var pendingPeek: DispatchWorkItem?
    private var pendingExpand: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?
    private var pendingShrink: DispatchWorkItem?

    /// How long the pointer has to rest on the notch before the island opens.
    private static let hoverToOpen: TimeInterval = 0.7
    /// The swell starts a moment later, so quick passes through the notch show nothing at all.
    private static let peekDelay: TimeInterval = 0.15
    private static let unpeekDuration: TimeInterval = 0.2
    private static let collapseDelay: TimeInterval = 0.25
    private static let collapseAfterCopy: TimeInterval = 0.5
    private static let collapseAnimationDuration: TimeInterval = 0.45

    init(store: ClipboardStore) {
        self.store = store

        container = IslandContainerView(frame: .zero)
        container.onEnter = { [weak self] in self?.mouseEntered() }
        container.onExit = { [weak self] in self?.mouseExited() }

        let hosting = IslandHostingView(rootView: IslandView(state: state, store: store, controller: self))
        hosting.sizingOptions = []
        hostingView = hosting
        container.addSubview(hosting)
        panel.contentView = container

        updateGeometry()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateGeometry() }
    }

    // MARK: Actions from the view

    func copy(_ item: ClipItem) {
        store.copy(item)
        scheduleCollapse(after: Self.collapseAfterCopy)
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            pendingCollapse?.cancel()
            pendingCollapse = nil
        } else if !panel.frame.contains(NSEvent.mouseLocation) {
            collapse()
        }
    }

    // MARK: Hover

    private func mouseEntered() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        guard !state.isExpanded else { return }
        if isClosing {
            // Came back while it was still closing: reopen right away.
            expand()
            return
        }
        startHoverTimer()
    }

    private func mouseExited() {
        cancelHoverTimer()
        if state.isExpanded {
            if !isDragging { scheduleCollapse(after: Self.collapseDelay) }
        } else if !isClosing {
            cancelPeek()
        }
    }

    /// Resting on the notch: swell after `peekDelay`, open after `hoverToOpen`. Leaving cancels both.
    private func startHoverTimer() {
        cancelHoverTimer()
        pendingShrink?.cancel()
        pendingShrink = nil

        let peek = DispatchWorkItem { [weak self] in self?.startPeek() }
        let open = DispatchWorkItem { [weak self] in self?.expand() }
        pendingPeek = peek
        pendingExpand = open
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekDelay, execute: peek)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverToOpen, execute: open)
    }

    private func cancelHoverTimer() {
        pendingPeek?.cancel()
        pendingPeek = nil
        pendingExpand?.cancel()
        pendingExpand = nil
    }

    private func startPeek() {
        pendingPeek = nil
        panel.setFrame(frame(for: state.peekSize), display: true)
        // The swell keeps growing until the island opens, so it doubles as a progress cue.
        withAnimation(.easeInOut(duration: Self.hoverToOpen - Self.peekDelay)) {
            state.isPeeking = true
        }
    }

    private func cancelPeek() {
        if state.isPeeking {
            withAnimation(.easeOut(duration: Self.unpeekDuration)) {
                state.isPeeking = false
            }
        }
        shrinkToNotch(after: Self.unpeekDuration)
    }

    // MARK: Expand / collapse

    private func expand() {
        cancelHoverTimer()
        pendingShrink?.cancel()
        pendingShrink = nil
        isClosing = false
        guard !state.isExpanded else { return }
        store.pruneMissingFiles()
        store.monitor?.refreshAccessState()
        panel.setFrame(frame(for: state.expandedSize), display: true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            state.isExpanded = true
            state.isPeeking = false
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        pendingCollapse?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        pendingCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func collapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        guard state.isExpanded, !isDragging else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
            state.isExpanded = false
        }
        isClosing = true
        shrinkToNotch(after: Self.collapseAnimationDuration)
    }

    /// Shrinks the window back to the notch once the shape has finished animating closed.
    private func shrinkToNotch(after delay: TimeInterval) {
        pendingShrink?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isExpanded, !self.state.isPeeking else { return }
            self.pendingShrink = nil
            self.isClosing = false
            self.panel.setFrame(self.frame(for: self.state.notchSize), display: true)
        }
        pendingShrink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Geometry

    private func updateGeometry() {
        guard let geometry = NotchGeometry.current() else { return }
        screenFrame = geometry.screen.frame
        centerX = geometry.centerX
        state.notchSize = geometry.size
        state.hasNotch = geometry.hasNotch
        // The SwiftUI content always has the largest (expanded) size; the window crops it.
        hostingView.setFrameSize(state.expandedSize)
        let size = state.isExpanded ? state.expandedSize : state.isPeeking ? state.peekSize : state.notchSize
        panel.setFrame(frame(for: size), display: true)
        container.centerSubviews()
    }

    /// A rect of `size` centred on the notch and pinned to the top edge of the island's screen.
    private func frame(for size: CGSize) -> NSRect {
        NSRect(
            x: (centerX - size.width / 2).rounded(),
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
