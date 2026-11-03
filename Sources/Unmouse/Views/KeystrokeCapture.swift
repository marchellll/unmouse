import AppKit
import SwiftUI
import UnmouseCore

/// Button that records the next keystroke (with modifiers) into a binding list.
struct KeystrokeCaptureRow: View {
    let title: String
    var hint: String? = nil
    @Binding var shortcuts: [String]
    var conflicts = false
    var onChange: () -> Void
    @State private var capturing = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let hint, !hint.isEmpty {
                OptionLabel(title: title, hint: hint)
                    .frame(maxWidth: 280, alignment: .leading)
            } else {
                Text(title)
                    .frame(width: 140, alignment: .leading)
            }
            Text(shortcuts.isEmpty ? "—" : shortcuts.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(conflicts ? Color.red : (shortcuts.isEmpty ? Color.secondary : Color.primary))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if capturing {
                KeyCaptureRepresentable { raw in
                    if !shortcuts.contains(raw) {
                        shortcuts.append(raw)
                    }
                    capturing = false
                    onChange()
                } onCancel: {
                    capturing = false
                }
                .frame(width: 1, height: 1)
                Text("Press key…")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(capturing ? "Cancel" : "Record") {
                capturing.toggle()
            }
            .buttonStyle(.bordered)
            Button("Clear") {
                shortcuts = []
                onChange()
            }
            .buttonStyle(.borderless)
            .disabled(shortcuts.isEmpty)
        }
        .modifier(OptionalHelp(hint: hint))
    }
}

/// Title stays with its hint. The control beside this stays vertically centered.
struct OptionLabel: View {
    var title: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OptionalHelp: ViewModifier {
    var hint: String?

    @ViewBuilder func body(content: Content) -> some View {
        if let hint, !hint.isEmpty {
            content.help(hint)
        } else {
            content
        }
    }
}

private struct KeyCaptureRepresentable: NSViewRepresentable {
    var onCapture: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

final class KeyCaptureView: NSView {
    var onCapture: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        if let raw = Self.shortcutString(from: event) {
            onCapture?(raw)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Bare modifier tap: capture on release when only that side is involved.
        guard let kind = KeyCodes.kind(from: CGKeyCode(event.keyCode)), kind.isModifier else { return }
        let down = Self.modifierDown(kind, flags: event.modifierFlags)
        if !down {
            onCapture?(kind.configToken)
        }
    }

    private static func shortcutString(from event: NSEvent) -> String? {
        guard let kind = KeyCodes.kind(from: CGKeyCode(event.keyCode)) else { return nil }
        if kind.isModifier {
            return kind.configToken
        }
        var mods: [String] = []
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if f.contains(.command) { mods.append("command") }
        if f.contains(.option) { mods.append("option") }
        if f.contains(.shift) { mods.append("shift") }
        if f.contains(.control) { mods.append("control") }
        let key = kind.configToken
        if mods.isEmpty { return key }
        return (mods.sorted() + [key]).joined(separator: "+")
    }

    private static func modifierDown(_ kind: KeyKind, flags: NSEvent.ModifierFlags) -> Bool {
        switch kind {
        case .commandLeft, .commandRight, .command: return flags.contains(.command)
        case .optionLeft, .optionRight, .option: return flags.contains(.option)
        case .shiftLeft, .shiftRight, .shift: return flags.contains(.shift)
        case .controlLeft, .controlRight, .control: return flags.contains(.control)
        case .fn: return flags.contains(.function)
        default: return false
        }
    }
}

import Carbon.HIToolbox
