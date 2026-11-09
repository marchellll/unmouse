import SwiftUI

struct WalkthroughView: View {
    @Bindable var model: AppModel
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Unmouse")
                .font(.title2.weight(.semibold))

            switch step {
            case 0:
                Text("Unmouse needs Accessibility to move the pointer and read on-screen controls.")
                Button("Continue") { step = 1 }
            case 1:
                Text("Turn on Unmouse in Accessibility.")
                Button("Open Accessibility Settings") {
                    model.requestAccessibility()
                    step = 2
                }
            case 2:
                Text("Waiting for Accessibility…")
                    .onAppear { pollAccessibility() }
                if model.accessibilityTrusted {
                    Text("Accessibility is on.").foregroundStyle(.green)
                    Button("Continue") { step = 3 }
                        .onAppear { step = 3 }
                }
            case 3:
                Text("Input Monitoring lets Unmouse see keys for its modes.")
                Button("Open Input Monitoring Settings") {
                    model.openInputMonitoringSettings()
                    step = 4
                }
            case 4:
                Text("Waiting for Input Monitoring…")
                    .onAppear { pollInput() }
                if model.inputMonitoringOK {
                    Text("Input Monitoring looks ready.").foregroundStyle(.green)
                    Button("Continue") { step = 5 }
                        .onAppear { step = 5 }
                }
            default:
                Text("You're set. Next: a short tutorial.")
                Button("Start tutorial") {
                    model.finishWalkthrough()
                }
            }

            Spacer()
            Button("Skip for now") {
                model.skipWalkthrough()
            }
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, height: 280)
        .onReceive(Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()) { _ in
            model.refreshPermissions()
            if step == 2, model.accessibilityTrusted { step = 3 }
            if step == 4, model.inputMonitoringOK { step = 5 }
        }
    }

    private func pollAccessibility() {
        model.refreshPermissions()
    }

    private func pollInput() {
        model.refreshPermissions()
    }
}
