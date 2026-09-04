import SwiftUI
import AppKit

/// The draggable divider above the transfer queue, implemented in AppKit.
///
/// Two reasons it isn't a SwiftUI `.onHover` + `DragGesture`:
///
/// - **Cursor.** `NSCursor.push()/pop()` is a stack, and `NSSplitView` pushes
///   and pops its own divider cursor. Coming off the local|remote divider onto
///   this handle, the split view's `pop` removed *our* cursor and left its own
///   in place, so the pointer never changed to ↕. Cursor rects and
///   `cursorUpdate:` don't use that stack and can't be unbalanced by a
///   neighbouring view.
/// - **Drag.** Handling the mouse here keeps the geometry absolute: the anchor
///   height is captured on mouse-down and each drag reports a target height, so
///   the panel moving under the pointer can't feed back into the gesture.
struct ResizeHandle: NSViewRepresentable {
    /// Panel height at the moment the drag starts.
    var currentHeight: () -> CGFloat
    /// Target height for this drag position, before clamping.
    var onDrag: (CGFloat) -> Void
    var onDragEnded: () -> Void
    /// Double-click: back to sizing from contents.
    var onReset: () -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        ResizeHandleView()
    }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        // Refreshed every render so the closures see current state.
        view.currentHeight = currentHeight
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        view.onReset = onReset
        view.onHover = onHover
    }
}

final class ResizeHandleView: NSView {
    var currentHeight: () -> CGFloat = { 0 }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    var onReset: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }

    private var anchorPointY: CGFloat?
    private var anchorHeight: CGFloat = 0

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover(true)
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard anchorPointY == nil else { return }  // keep it lit while dragging
        onHover(false)
    }

    // MARK: Drag

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onReset()
            return
        }
        anchorPointY = event.locationInWindow.y
        anchorHeight = currentHeight()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchorPointY else { return }
        // Window coordinates are y-up, so dragging up grows the panel.
        onDrag(anchorHeight + (event.locationInWindow.y - anchorPointY))
    }

    override func mouseUp(with event: NSEvent) {
        guard anchorPointY != nil else { return }
        anchorPointY = nil
        onDragEnded()
        if !bounds.contains(convert(event.locationInWindow, from: nil)) {
            onHover(false)
        }
    }
}
