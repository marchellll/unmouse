import SwiftUI
import UnmouseCore

struct CoachView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tutorial = model.tutorial, let step = tutorial.current {
                Text(tutorial.session.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(step.prompt)
                    .font(.callout)
                HStack(spacing: 4) {
                    ForEach(0..<tutorial.steps.count, id: \.self) { i in
                        Circle()
                            .fill(i <= tutorial.stepIndex ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            } else {
                Text(modeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }

    private var modeTitle: String {
        switch model.mode {
        case .idle: "Idle"
        case .grid: "Grid"
        case .free: "Free"
        case .hint: "Hint"
        }
    }

    private var lines: [String] {
        let b = model.config.bindings
        switch model.mode {
        case .idle:
            return [
                "Grid  \(b.global.gridMode.joined(separator: " / "))",
                "Free  \(b.global.freeMode.joined(separator: " / "))",
                "Hint  \(b.global.hintMode.joined(separator: " / "))",
            ]
        case .grid:
            return [
                "Type cell · Space click · A right · D move",
                "Option → free · Delete back · Esc cancel",
            ]
        case .free:
            return [
                "HJKL move · Z fast · X slow",
                "Space click · Q drag · Esc leave",
            ]
        case .hint:
            return [
                "Type code · Space click · A right · D move",
                "Delete back · Esc cancel",
            ]
        }
    }
}
