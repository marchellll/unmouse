import SwiftUI
import UnmouseCore

/// Draggable speed curve. X is how long a direction key has been held. Y is fraction of top speed.
struct AccelCurveEditor: View {
    @Binding var knots: [SpeedKnot]
    var duration: Double
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let plot = Self.plotRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    Self.draw(context: context, size: size, knots: knots, duration: duration)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .named("accel")).onEnded { value in
                        add(at: value.location, plot: plot)
                    }
                )
                ForEach(Array(knots.indices), id: \.self) { index in
                    handle(index: index, plot: plot)
                }
            }
            .coordinateSpace(name: "accel")
        }
        .frame(height: 156)
        .accessibilityLabel("Speed curve")
    }

    private func handle(index: Int, plot: CGRect) -> some View {
        let spot = Self.location(of: knots[index], in: plot, duration: duration)
        let removable = knots.count > 2 && index > 0 && index < knots.count - 1
        let dot = Circle()
            .fill(Color.primary)
            .frame(width: 9, height: 9)
            .frame(width: Self.handleSize, height: Self.handleSize)
            .contentShape(Circle())
            .offset(x: spot.x - Self.handleSize / 2, y: spot.y - Self.handleSize / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("accel"))
                    .onChanged { value in
                        move(index, to: value.location, plot: plot)
                    }
                    .onEnded { _ in
                        onCommit()
                    }
            )
        return Group {
            if removable {
                dot.contextMenu {
                    Button("Remove point") {
                        var next = knots
                        next.remove(at: index)
                        knots = AccelCurve.normalized(next, duration: duration)
                        onCommit()
                    }
                }
            } else {
                dot
            }
        }
    }

    private func move(_ index: Int, to point: CGPoint, plot: CGRect) {
        guard knots.indices.contains(index) else { return }
        let raw = Self.values(at: point, plot: plot, duration: duration)
        var next = knots
        if index == 0 || index == next.count - 1 {
            next[index].y = raw.y
        } else {
            let lower = next[index - 1].t + 0.12
            let upper = next[index + 1].t - 0.12
            guard upper > lower else { return }
            next[index].t = min(upper, max(lower, raw.t))
            next[index].y = raw.y
        }
        knots = next
    }

    private func add(at point: CGPoint, plot: CGRect) {
        guard knots.count < 8, plot.contains(point) else { return }
        if knots.contains(where: { knot in
            let placed = Self.location(of: knot, in: plot, duration: duration)
            return hypot(placed.x - point.x, placed.y - point.y) < 20
        }) {
            return
        }
        let raw = Self.values(at: point, plot: plot, duration: duration)
        guard raw.t > 0.08, raw.t < duration - 0.08 else { return }
        var next = knots
        next.append(SpeedKnot(t: raw.t, y: raw.y))
        knots = AccelCurve.normalized(next, duration: duration)
        onCommit()
    }

    private static func draw(context: GraphicsContext, size: CGSize, knots: [SpeedKnot], duration: Double) {
        let plot = plotRect(in: size)
        let card = Path(roundedRect: plot, cornerRadius: 6)
        context.fill(card, with: .color(.primary.opacity(0.05)))
        context.stroke(card, with: .color(.primary.opacity(0.16)), lineWidth: 1)

        let caption = Font.caption2
        if duration > 3.2 {
            let mark = location(of: SpeedKnot(t: 3, y: 0), in: plot, duration: duration).x
            var guide = Path()
            guide.move(to: CGPoint(x: mark, y: plot.minY))
            guide.addLine(to: CGPoint(x: mark, y: plot.maxY))
            context.stroke(
                guide,
                with: .color(.secondary.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.draw(Text("3s").font(caption).foregroundStyle(.secondary), at: CGPoint(x: mark, y: plot.maxY + 3), anchor: .top)
        }

        var line = Path()
        let samples = 72
        for step in 0...samples {
            let t = duration * Double(step) / Double(samples)
            let point = location(of: SpeedKnot(t: t, y: AccelCurve.fraction(knots: knots, at: t)), in: plot, duration: duration)
            if step == 0 {
                line.move(to: point)
            } else {
                line.addLine(to: point)
            }
        }
        var fill = line
        fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        fill.closeSubpath()
        context.fill(fill, with: .color(.primary.opacity(0.08)))
        context.stroke(line, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        context.draw(Text("0s").font(caption).foregroundStyle(.secondary), at: CGPoint(x: plot.minX, y: plot.maxY + 3), anchor: .topLeading)
        context.draw(Text(secondsText(duration)).font(caption).foregroundStyle(.secondary), at: CGPoint(x: plot.maxX, y: plot.maxY + 3), anchor: .topTrailing)
    }

    private static func secondsText(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return "\(Int(value.rounded()))s"
        }
        return String(format: "%.1fs", value)
    }

    private static let handleSize: CGFloat = 22

    private static func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 8, y: 12, width: max(1, size.width - 16), height: max(1, size.height - 32))
    }

    private static func location(of knot: SpeedKnot, in plot: CGRect, duration: Double) -> CGPoint {
        CGPoint(
            x: plot.minX + CGFloat(knot.t / duration) * plot.width,
            y: plot.minY + CGFloat(1 - knot.y) * plot.height
        )
    }

    private static func values(at point: CGPoint, plot: CGRect, duration: Double) -> (t: Double, y: Double) {
        let t = Double((point.x - plot.minX) / plot.width) * duration
        let y = 1 - Double((point.y - plot.minY) / plot.height)
        return (min(duration, max(0, t)), min(1, max(0, y)))
    }
}
