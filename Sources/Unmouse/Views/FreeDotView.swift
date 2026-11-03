import SwiftUI

struct FreeDotView: View {
    @Bindable var model: AppModel

    var body: some View {
        Canvas { context, size in
            let fill = Color(hex: model.config.colors.freeDot) ?? .white
            let halo = Color(hex: model.config.colors.freeDotHalo) ?? .black
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(halo.opacity(0.7)))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(fill))
            if model.dragging {
                context.fill(Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)), with: .color(fill))
            }
        }
        .allowsHitTesting(false)
    }
}
