import SwiftUI
import UnrestorCore

@main
struct UnrestorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.decision.hold ? "eye.fill" : "eye.slash")
                .accessibilityLabel(model.decision.hold ? "Unrestor: keeping Mac awake" : "Unrestor: idle")
                .task {
                    model.start()
                    model.refreshLaunchAtLogin()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

/// A popover with a status header and an on/off switch, then holds and limits.
private struct MenuContent: View {
    @Bindable var model: AppModel

    private let durations: [(String, TimeInterval)] = [
        ("30m", 1_800), ("1h", 3_600), ("2h", 7_200), ("4h", 14_400), ("8h", 28_800),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if model.manualRequest == nil {
                divider
                durationRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            if case .needsSetup = model.service {
                divider
                setupRow.padding(16)
            }

            let others = model.requests.filter { $0.id != HoldRequest.manualID }
            if !others.isEmpty {
                divider
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(others, id: \.id) { request in
                        HStack {
                            Image(systemName: "terminal").foregroundStyle(.secondary)
                            Text(request.label).lineLimit(1)
                            if let pid = request.pid {
                                Text("pid \(pid)").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .font(.callout)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            divider
            limits
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            divider
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
    }

    private var divider: some View { Divider().padding(.horizontal, 12) }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.decision.hold ? "Awake" : "Resting")
                    .font(.body.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.decision.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle("Keep Mac awake", isOn: Binding(
                get: { model.manualRequest != nil },
                set: { model.setManualHold($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityHint("Keeps this Mac awake, lid closed, until you turn it off")
        }
    }

    private var durationRow: some View {
        HStack(spacing: 6) {
            Text("Awake for").font(.caption).foregroundStyle(.secondary)
            Spacer()
            ForEach(durations, id: \.1) { name, seconds in
                Button(name) { model.setManualHold(true, for: seconds) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var setupRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .needsSetup(let message) = model.service {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Button("Set Up Background Service…") { model.setUpService() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Only while connected to power", isOn: $model.settings.onlyWhileConnectedToPower)
            Toggle("Use Low Power Mode while awake", isOn: $model.settings.lowPowerWhileHeld)
            Picker("Let Mac sleep below", selection: $model.settings.batteryFloor) {
                ForEach([10, 20, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
            Spacer()
            Button("Quit") {
                model.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
