import AppKit
import SwiftUI

/// Shared between the controller (which owns the window) and the SwiftUI view (which draws it).
final class IslandState: ObservableObject {
    @Published var isExpanded = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = true

    var expandedSize: CGSize {
        CGSize(width: 520, height: notchSize.height + 244)
    }
}

/// Where the notch is on the current setup.
struct NotchGeometry {
    let screen: NSScreen
    let size: CGSize
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
                    hasNotch: true
                )
            }
        }
        // No notch (lid closed on an external display): an invisible hover zone in the menu bar.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screen: screen, size: CGSize(width: 200, height: menuBarHeight), hasNotch: false)
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

/// Event-driven hover detection for the whole panel; no mouse polling, no Accessibility permission.
private final class HoverTrackingView: NSView {
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
}

final class IslandController {
    let store: ClipboardStore
    let state = IslandState()

    private let panel = IslandPanel()
    private var screenFrame: NSRect = .zero
    private var isDragging = false
    private var pendingExpand: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?
    private var pendingShrink: DispatchWorkItem?

    private static let expandDwell: TimeInterval = 0.12
    private static let collapseDelay: TimeInterval = 0.25
    private static let collapseAfterCopy: TimeInterval = 0.5
    private static let collapseAnimationDuration: TimeInterval = 0.45

    init(store: ClipboardStore) {
        self.store = store

        let container = HoverTrackingView(frame: .zero)
        container.onEnter = { [weak self] in self?.mouseEntered() }
        container.onExit = { [weak self] in self?.mouseExited() }

        let hosting = IslandHostingView(rootView: IslandView(state: state, store: store, controller: self))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
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
        if pendingShrink != nil {
            // Came back while it was still closing: reopen right away.
            expand()
            return
        }
        // Short dwell so passing through the notch on the way to a menu doesn't open it.
        let work = DispatchWorkItem { [weak self] in self?.expand() }
        pendingExpand = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.expandDwell, execute: work)
    }

    private func mouseExited() {
        pendingExpand?.cancel()
        pendingExpand = nil
        guard state.isExpanded, !isDragging else { return }
        scheduleCollapse(after: Self.collapseDelay)
    }

    // MARK: Expand / collapse

    private func expand() {
        pendingExpand = nil
        pendingShrink?.cancel()
        pendingShrink = nil
        guard !state.isExpanded else { return }
        store.pruneMissingFiles()
        store.monitor?.refreshAccessState()
        panel.setFrame(frame(for: state.expandedSize), display: true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            state.isExpanded = true
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
        // Shrink the window back to the notch once the shape has finished closing.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.pendingShrink = nil
            self.panel.setFrame(self.frame(for: self.state.notchSize), display: true)
        }
        pendingShrink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseAnimationDuration, execute: work)
    }

    // MARK: Geometry

    private func updateGeometry() {
        guard let geometry = NotchGeometry.current() else { return }
        screenFrame = geometry.screen.frame
        state.notchSize = geometry.size
        state.hasNotch = geometry.hasNotch
        panel.setFrame(frame(for: state.isExpanded ? state.expandedSize : state.notchSize), display: true)
    }

    /// A rect of `size` centred horizontally and pinned to the top edge of the island's screen.
    private func frame(for size: CGSize) -> NSRect {
        NSRect(
            x: (screenFrame.midX - size.width / 2).rounded(),
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
