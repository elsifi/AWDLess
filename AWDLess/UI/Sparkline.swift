import SwiftUI

/// 60-second round-trip sparkline. Timeouts are drawn as full-height red bars.
struct Sparkline: View {
    let health: LinkHealth
    var body: some View {
        GeometryReader { geo in
            let samples = health.samples
            let n = LinkHealth.windowSize
            let w = geo.size.width / CGFloat(n)
            let maxMs = max(health.stallThresholdMs * 1.2, (health.maximum ?? 0) * 1.1, 50)
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4))
                Path { p in
                    let y = geo.size.height * (1 - CGFloat(health.stallThresholdMs / maxMs))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }.stroke(.red.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<n, id: \.self) { i in
                        let idx = i - (n - samples.count)
                        let sample: Double?? = idx >= 0 ? samples[idx] : nil
                        bar(sample, width: w, height: geo.size.height, maxMs: maxMs)
                    }
                }
            }
        }
    }
    @ViewBuilder private func bar(_ sample: Double??, width: CGFloat, height: CGFloat, maxMs: Double) -> some View {
        switch sample {
        case .none: Color.clear.frame(width: width, height: 1)
        case .some(nil): Rectangle().fill(.red).frame(width: max(width - 1, 1), height: height)
        case .some(.some(let ms)):
            let level = health.level(of: ms)
            let color: Color = level == .good ? .green : (level == .degraded ? .orange : .red)
            Rectangle().fill(color).frame(width: max(width - 1, 1), height: max(2, height * CGFloat(min(ms / maxMs, 1))))
        }
    }
}
