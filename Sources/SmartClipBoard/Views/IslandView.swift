import SwiftUI

/// Black notch silhouette: top corners curve outward into the menu bar, bottom corners are rounded.
/// Both radii animate, so the island looks like it pours out of the notch.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                          control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                          control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                          control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var store: ClipboardStore
    let controller: IslandController

    static let flareRadius: CGFloat = 14

    var body: some View {
        let size = state.isExpanded ? state.expandedSize : state.notchSize
        let shape = NotchShape(
            topRadius: state.isExpanded ? Self.flareRadius : 0,
            bottomRadius: state.isExpanded ? 28 : 10
        )

        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if state.isExpanded {
                IslandContent(store: store, controller: controller)
                    .padding(.top, state.notchSize.height)
                    .padding(.horizontal, Self.flareRadius)
                    .frame(width: state.expandedSize.width, height: state.expandedSize.height, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.92, anchor: .top))
                            .combined(with: .modifier(active: BlurEffect(radius: 6), identity: BlurEffect(radius: 0)))
                            .animation(.spring(response: 0.38, dampingFraction: 0.85).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        // On a screen without a notch the collapsed hover zone is invisible.
        .opacity(state.hasNotch || state.isExpanded ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

private struct BlurEffect: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// Everything below the physical notch: header, words, divider, media.
private struct IslandContent: View {
    @ObservedObject var store: ClipboardStore
    let controller: IslandController

    @State private var hoveredWord: ClipItem.ID?
    @State private var hoveredMedia: ClipItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            wordsSection
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 2)
            mediaSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let item = store.words.first(where: { $0.id == hoveredWord }) {
                    Text(item.preview).foregroundStyle(.white.opacity(0.85))
                } else if store.accessDenied {
                    Text("Clipboard access is off: System Settings › Privacy & Security › Paste from Other Apps")
                        .foregroundStyle(.orange)
                } else {
                    sectionTitle("Words", count: store.words.count, paused: store.isPaused)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 8)

            HeaderButton(symbol: store.isPaused ? "play.fill" : "pause.fill") { store.isPaused.toggle() }
            HeaderButton(symbol: "trash") { store.clearAll() }
            HeaderButton(symbol: "power") { NSApp.terminate(nil) }
        }
        .frame(height: 16)
    }

    private func sectionTitle(_ title: String, count: Int, paused: Bool = false) -> Text {
        Text(title).foregroundStyle(.white.opacity(0.55))
            + Text("  \(count)").foregroundStyle(.white.opacity(0.3))
            + Text(paused ? "  · paused" : "").foregroundStyle(.orange.opacity(0.8))
    }

    // MARK: Words

    private var wordsSection: some View {
        Group {
            if store.words.isEmpty {
                emptyHint("Copy some text and it'll show up here")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: 6) {
                        ForEach(store.words) { item in
                            WordChip(
                                item: item,
                                isCopied: store.lastCopiedID == item.id,
                                isHovered: hoveredWord == item.id,
                                onHover: { setHover($0, item.id, &hoveredWord) },
                                onClick: { controller.copy(item) },
                                onRemove: { store.remove(item) },
                                onDragChange: { controller.setDragging($0) }
                            )
                        }
                    }
                }
            }
        }
        .frame(height: 88, alignment: .top)
    }

    // MARK: Media

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let item = store.media.first(where: { $0.id == hoveredMedia }) {
                    Text(item.preview).foregroundStyle(.white.opacity(0.85))
                } else {
                    sectionTitle("Media", count: store.media.count)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)

            if store.media.isEmpty {
                emptyHint("Copy a photo, GIF or video")
                    .frame(height: 70, alignment: .top)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(store.media) { item in
                            MediaTile(
                                item: item,
                                thumbnail: store.thumbnails[item.id],
                                isCopied: store.lastCopiedID == item.id,
                                isHovered: hoveredMedia == item.id,
                                onHover: { setHover($0, item.id, &hoveredMedia) },
                                onClick: { controller.copy(item) },
                                onRemove: { store.remove(item) },
                                onDragChange: { controller.setDragging($0) }
                            )
                        }
                    }
                    .padding(.horizontal, 3)
                    .frame(height: 70)
                }
                .frame(height: 70)
            }
        }
    }

    // MARK: Helpers

    private func setHover(_ hovering: Bool, _ id: ClipItem.ID, _ hovered: inout ClipItem.ID?) {
        if hovering {
            hovered = id
        } else if hovered == id {
            hovered = nil
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.3))
            .padding(.top, 4)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered ? 0.9 : 0.45))
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
