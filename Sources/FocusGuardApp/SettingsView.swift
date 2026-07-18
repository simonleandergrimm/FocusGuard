import AppKit
import FocusGuardCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apiKey = ""
    @State private var modelName = ModelSettings.current()
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $apiKey)
                TextField("Model", text: $modelName)
                Text("FocusGuard defaults to gpt-5.6-terra with medium reasoning. You can enter another Responses API model here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The key is stored in this Mac user's Keychain and is sent only to api.openai.com. Use a newly created project key—not one previously pasted into a chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Background reliability") {
                Toggle(
                    "Launch FocusGuard at login",
                    isOn: Binding(
                        get: { model.launchAtLoginDesired },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                Text(model.loginItemStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.loginItemState == .requiresApproval || model.loginItemState == .unavailable {
                    Button("Open Login Items settings") {
                        model.openLoginItemSettings()
                    }
                }

                LabeledContent("Privileged helper", value: model.helperStatusText)
                if let helperHealthDetails = model.helperHealthDetails {
                    Text(helperHealthDetails)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.helperState.needsRepair {
                    Button(model.isInstallingHelper ? "Setting up helper…" : model.helperActionTitle) {
                        model.installHelper()
                    }
                    .disabled(model.isInstallingHelper)
                }
                if !model.backgroundStatusMessage.isEmpty {
                    Text(model.backgroundStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recurring warnings") {
                Toggle(
                    "Warn 5 minutes before recurring blocks",
                    isOn: Binding(
                        get: { model.recurringWarningsEnabled },
                        set: { model.setRecurringWarningsEnabled($0) }
                    )
                )
                Text(model.recurringWarningStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser landing pages") {
                Text("Click Export and show extension first. Then, in Chrome, Brave, or Edge, enable Developer mode on the Extensions page, choose Load unpacked, and select the Finder folder that opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("~/Library/Application Support/FocusGuard/BrowserExtension")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                HStack {
                    Label("Local only · no browsing data leaves this Mac", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export and show extension") { revealBrowserExtension() }
                }

                Text("Browsers with Secure DNS (DNS over HTTPS) enabled bypass the hosts-file blocking entirely. Install the extension, or turn off Secure DNS in the browser, to keep website blocks reliable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 620)
        .preferredColorScheme(.light)
        .onAppear {
            do {
                apiKey = try APIKeyStore.read() ?? ""
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            try APIKeyStore.save(apiKey)
            ModelSettings.save(modelName)
            modelName = ModelSettings.current()
            statusMessage = "Saved to this Mac"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func revealBrowserExtension() {
        do {
            let extensionURL = try BrowserExtensionExporter.export()
            guard NSWorkspace.shared.open(extensionURL) else {
                statusMessage = "The extension was exported, but Finder did not open."
                return
            }
            statusMessage = "Extension exported to Application Support and opened in Finder"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

