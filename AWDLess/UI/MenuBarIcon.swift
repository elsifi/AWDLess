import AppKit

/// Template menu bar icon. Three styles; state is shown by the glyph variant and a small badge.
enum MenuBarIcon {
    enum State { case helperMissing, standby, protecting, protectingStalling, manualOn, ethernet }
    enum Style: String, CaseIterable, Identifiable {
        case camera, shield, antenna
        var id: String { rawValue }
        var label: String { switch self { case .camera: "Camera"; case .shield: "Shield"; case .antenna: "Antenna" } }
    }

    static func symbol(for state: State, style: Style) -> String {
        switch style {
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
}
