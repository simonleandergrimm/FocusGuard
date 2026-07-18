import AppKit
import FocusGuardCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apiKey = ""
    @State private var modelName = ModelSettings.current()
    @State private var statusMessage = ""
    @AppStorage("showMenuBarStatus") private var showMenuBarStatus = true

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

            Section("Menu bar") {
                Toggle("Show FocusGuard status in the menu bar", isOn: $showMenuBarStatus)
                Text("The shield fills while a block is active; the dropdown lists active sessions with their remaining time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Open setup, remove any older FocusGuard extension that points somewhere else, then choose Load unpacked and select the Finder folder FocusGuard opens.")
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
                    Button("Open extension setup") { revealBrowserExtension() }
                }

                Text("Browser DNS behavior varies. Install the extension for reliable HTTPS and subdomain coverage; if a browser still bypasses a block, review its Secure DNS settings.")
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
            let openedFinder = NSWorkspace.shared.open(extensionURL)
            let openedBrowser = openChromiumExtensionsPage()
            guard openedFinder else {
                statusMessage = "The extension was exported, but Finder did not open."
                return
            }
            statusMessage = openedBrowser
                ? "In Chrome, replace any older FocusGuard entry, then Load unpacked from the Finder folder."
                : "Extension exported. Open your browser's Extensions page, then Load unpacked from the Finder folder."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openChromiumExtensionsPage() -> Bool {
        let candidates = ["Google Chrome", "Brave Browser", "Microsoft Edge"]
        guard let browser = candidates.first(where: {
            FileManager.default.fileExists(atPath: "/Applications/\($0).app")
        }) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", browser, "chrome://extensions/"]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
