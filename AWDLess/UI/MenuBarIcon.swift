import AppKit

/// Template menu bar icon. Three styles; state is shown by the glyph variant and a small badge.
enum MenuBarIcon {
    enum State { case helperMissing, standby, protecting, protectingStalling, manualOn, ethernet }
    enum Style: String, CaseIterable, Identifiable {
        case link, camera, shield, antenna
        var id: String { rawValue }
        var label: String { switch self { case .link: "Two Macs"; case .camera: "Camera"; case .shield: "Shield"; case .antenna: "Antenna" } }
    }

    static func symbol(for state: State, style: Style) -> String {
        switch style {
        case .link: return "video" // unused; drawn by linkImage
        case .camera:
            switch state {
            case .helperMissing: return "video.badge.ellipsis"
            case .standby, .ethernet: return "video"
            case .protecting: return "video.fill"
            case .protectingStalling: return "video.badge.waveform"
            case .manualOn: return "video.slash"
            }
        case .shield:
            switch state {
            case .helperMissing: return "shield.slash"
            case .standby, .ethernet: return "shield"
            case .protecting: return "checkmark.shield.fill"
            case .protectingStalling: return "exclamationmark.shield.fill"
            case .manualOn: return "shield.lefthalf.filled"
            }
        case .antenna:
            switch state {
            case .helperMissing: return "antenna.radiowaves.left.and.right.circle"
            case .standby, .ethernet: return "antenna.radiowaves.left.and.right"
            case .protecting, .protectingStalling: return "antenna.radiowaves.left.and.right.slash"
            case .manualOn: return "antenna.radiowaves.left.and.right.circle.fill"
            }
        }
    }

    static func image(for state: State, style: Style) -> NSImage {
        if style == .link { return linkImage(for: state) }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let name = symbol(for: state, style: style)
        let base = (NSImage(systemSymbolName: name, accessibilityDescription: "AWDLess")
                    ?? NSImage(systemSymbolName: "video", accessibilityDescription: "AWDLess")!)
            .withSymbolConfiguration(config)!
        base.isTemplate = true
        // Antenna style has no stall variant: add a dot badge.
        guard style == .antenna, state == .protectingStalling else { return base }
        let img = NSImage(size: NSSize(width: base.size.width + 3, height: base.size.height), flipped: false) { rect in
            base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - "Two Macs" glyph (concept A): two Macs joined by the Universal Control link.
    // Standing by: solid link. Meeting: link dashed and cut. Stalling: dot badge. Helper missing: hollow badge.

    private static func linkImage(for state: State) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            func stroke(_ p: NSBezierPath, _ w: CGFloat) { p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke() }
            func laptop(_ o: CGPoint) {
                stroke(NSBezierPath(roundedRect: NSRect(x: o.x, y: o.y + 1.6, width: 7, height: 4.6), xRadius: 0.9, yRadius: 0.9), 1.3)
                let base = NSBezierPath(); base.move(to: NSPoint(x: o.x - 1, y: o.y + 0.5)); base.line(to: NSPoint(x: o.x + 8, y: o.y + 0.5)); stroke(base, 1.3)
            }
            laptop(NSPoint(x: 1.5, y: 1)); laptop(NSPoint(x: 13.5, y: 10))
            let link = NSBezierPath(); link.move(to: NSPoint(x: 8.8, y: 5.6)); link.line(to: NSPoint(x: 13.6, y: 11.4))
            let cut = state == .protecting || state == .protectingStalling
            if cut { link.setLineDash([1.6, 2.2], count: 2, phase: 0) }
            stroke(link, 1.5)
            if cut {
                let s = NSBezierPath(); s.move(to: NSPoint(x: 13.4, y: 5.8)); s.line(to: NSPoint(x: 9, y: 11.2)); stroke(s, 1.8)
            }
            switch state {
            case .protectingStalling: NSBezierPath(ovalIn: NSRect(x: 17, y: 0, width: 4.5, height: 4.5)).fill()
            case .helperMissing: stroke(NSBezierPath(ovalIn: NSRect(x: 16.5, y: 0.5, width: 4.5, height: 4.5)), 1.2)
            default: break
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
