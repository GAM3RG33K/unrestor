import SwiftUI
import UnrestorCore

@main
struct UnrestorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            HStack(spacing: 4) {
                MenuBarGlyph.image(awake: model.decision.hold)
                if let left = model.countdown {
                    Text(DurationParser.clock(left)).monospacedDigit()
                }
            }
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

            switch model.service {
            case .notInstalled, .failed:
                divider
                setupRow.padding(16)
            default:
                EmptyView()
            }

            if model.serviceNeedsUpdate {
                divider
                serviceUpdateRow.padding(16)
            }

            if let banner = updateBanner {
                divider
                banner.padding(16)
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
                HStack(spacing: 8) {
                    Text(model.decision.hold ? "Awake" : "Resting")
                        .font(.body.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let left = model.countdown {
                        Text(DurationParser.clock(left))
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("\(DurationParser.format(left)) left")
                        Text("left").font(.caption).foregroundStyle(.secondary)
                    }
                }
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
        VStack(alignment: .leading, spacing: 10) {
            switch model.service {
            case .notInstalled:
                Text("One-time setup")
                    .font(.callout.weight(.semibold))
                Text("Unrestor needs a small background service to keep the Mac awake with the lid closed. macOS will ask for your password once.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(model.installing ? "Installing…" : "Install Background Service…") {
                    model.installService()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.installing)
                HStack {
                    Button("Copy Terminal command") { model.copyInstallCommand() }
                    Button("Help") { model.openHelp() }
                }
                .buttonStyle(.link)
                .font(.caption)
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Reinstall…") { model.installService() }
                    Button("Help") { model.openHelp() }
                }
                .buttonStyle(.link)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serviceUpdateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The background service is out of date")
                .font(.callout.weight(.semibold))
            Text("It is version \(model.serviceVersion ?? "?"); this app is \(UnrestorVersion.current). Update it so they match. macOS asks for your password.")
                .font(.callout).foregroundStyle(.secondary)
            Button(model.installing ? "Updating…" : "Update Background Service…") { model.installService() }
                .buttonStyle(.borderedProminent)
                .disabled(model.installing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown only when there is something to say: an update, progress, or a failure.
    private var updateBanner: AnyView? {
        let updater = model.updater
        switch updater.state {
        case .available(let release):
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                Text("Unrestor \(release.version.description) is available")
                    .font(.callout.weight(.semibold))
                Text(updater.source == .direct
                     ? "You have \(UnrestorVersion.current). Unrestor restarts to finish. A manual hold ends; commands you started keep running."
                     : "You have \(UnrestorVersion.current). Installed with Homebrew, so Terminal opens and runs the upgrade, then restarts the background service. It asks for your password there.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Download & Install") { Task { await updater.install() } }
                        .buttonStyle(.borderedProminent)
                    Button("What's New") { updater.openReleasePage() }
                        .buttonStyle(.link)
                }
            }.frame(maxWidth: .infinity, alignment: .leading))
        case .handedToTerminal:
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                Text("Finish in Terminal").font(.callout.weight(.semibold))
                Text("Homebrew is updating Unrestor, which then restarts. Enter your password in Terminal when it asks, to restart the background service.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading))
        case .downloading, .verifying, .installing:
            let text: String = {
                switch updater.state {
                case .downloading: "Downloading the update…"
                case .verifying: "Checking the download…"
                default: "Installing. Unrestor will restart."
                }
            }()
            return AnyView(HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text).font(.callout)
                Spacer()
            })
        case .failed(let message, _):
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                Text("Update problem").font(.callout.weight(.semibold))
                Text(message).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Try Again") { Task { await updater.check() } }
                    Button("Open Release Page") { updater.openReleasePage() }
                }
                .buttonStyle(.link)
            }.frame(maxWidth: .infinity, alignment: .leading))
        default:
            return nil
        }
    }

    private var updateStatusText: String {
        switch model.updater.state {
        case .checking: return "Checking for updates…"
        case .upToDate: return "Up to date"
        case .available: return "Update available"
        default:
            if let last = model.updater.lastChecked {
                return "Checked " + last.formatted(.relative(presentation: .named))
            }
            return "Not checked yet"
        }
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Only while connected to power", isOn: $model.settings.onlyWhileConnectedToPower)
            Toggle("Use Low Power Mode while awake", isOn: $model.settings.lowPowerWhileHeld)
            Picker("Let Mac sleep below", selection: $model.settings.batteryFloor) {
                ForEach([10, 20, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
            }
            Toggle("Check for updates automatically", isOn: $model.settings.checkForUpdates)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.callout)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Unrestor \(UnrestorVersion.current)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("·").font(.caption).foregroundStyle(.secondary)
                Text(updateStatusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates") { Task { await model.updater.check() } }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(model.updater.isBusy)
            }
            footerControls
        }
    }

    private var footerControls: some View {
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
