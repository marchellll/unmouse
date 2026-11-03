import SwiftUI
import UnmouseCore

struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Unmouse")
                    .font(.headline)
                Spacer()
                Text(model.mode.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            permissionRow(
                title: "Accessibility",
                ok: model.accessibilityTrusted,
                actionTitle: "Grant",
                action: { model.requestAccessibility() }
            )
            permissionRow(
                title: "Input Monitoring",
                ok: model.inputMonitoringOK,
                actionTitle: "Open Settings",
                action: { model.openInputMonitoringSettings() }
            )

            Text(model.karabinerStatus.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let err = model.configError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Menu("Tutorial") {
                Button("Install walkthrough") { model.showWalkthrough = true }
                ForEach(TutorialSessionID.allCases, id: \.self) { session in
                    Button(session.title) { model.startTutorial(session) }
                }
            }

            Toggle("Coach", isOn: $model.coachEnabled)
                .help("While a mode is on, shows what you can do next.")
                .onChange(of: model.coachEnabled) { _, _ in
                    model.overlayController?.updateCoach()
                }

            Button("Settings…") { SettingsWindowController.shared.show(model: model) }
            Button("Quit Unmouse") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func permissionRow(title: String, ok: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            if !ok {
                Button(actionTitle, action: action)
            }
        }
        .font(.callout)
    }
}

import AppKit
