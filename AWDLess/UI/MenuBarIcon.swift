import AppKit

/// Template menu bar icon with a small badge for link stalls. Template images follow the
/// menu bar's light/dark appearance, so state is shown by shape, not colour.
enum MenuBarIcon {
    enum State { case helperMissing, idle, active, activeStalling, manualOn }

    static func image(for state: State) -> NSImage {
        let symbol: String
        switch state {
        case .helperMissing: symbol = "exclamationmark.triangle"
        case .idle: symbol = "antenna.radiowaves.left.and.right"
        case .active, .activeStalling: symbol = "antenna.radiowaves.left.and.right.slash"
        case .manualOn: symbol = "antenna.radiowaves.left.and.right.circle"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "AWDLess")!.withSymbolConfiguration(config)!
        guard state == .activeStalling else { base.isTemplate = true; return base }
        let size = NSSize(width: base.size.width + 4, height: base.size.height)
        let img = NSImage(size: size, flipped: false) { rect in
            base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5))
            NSColor.black.setFill(); dot.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
