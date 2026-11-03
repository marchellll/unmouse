import AppKit
import SwiftUI

enum ColorHex {
    static func color(from hex: String) -> Color {
        Color(hex: hex) ?? .white
    }

    static func hex(from color: Color, keepAlpha: Bool = true) -> String {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        let a = Int(round(rgb.alphaComponent * 255))
        if keepAlpha, a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct HexColorPicker: View {
    let title: String
    var hint: String? = nil
    @Binding var hex: String
    var onChange: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let hint, !hint.isEmpty {
                OptionLabel(title: title, hint: hint)
                    .frame(maxWidth: 280, alignment: .leading)
            } else {
                Text(title)
                    .frame(width: 140, alignment: .leading)
            }
            swatch
        }
        .modifier(OptionalHelp(hint: hint))
    }

    private var swatch: some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(ColorHex.color(from: hex))
                .frame(width: 28, height: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
                }
            ColorPicker(
                title,
                selection: Binding(
                    get: { ColorHex.color(from: hex) },
                    set: { newColor in
                        hex = ColorHex.hex(from: newColor)
                        onChange()
                    }
                ),
                supportsOpacity: true
            )
            .labelsHidden()
            TextField("Hex", text: Binding(
                get: { hex },
                set: { hex = $0; onChange() }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(width: 100)
        }
    }
}
