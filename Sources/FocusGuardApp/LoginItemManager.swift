import Foundation
import ServiceManagement

enum LoginItemState: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var description: String {
        switch self {
        case .enabled: "FocusGuard will open automatically when you log in."
        case .disabled: "FocusGuard will not open automatically."
        case .requiresApproval: "Allow FocusGuard under System Settings → General → Login Items."
        case .unavailable: "macOS could not find the registered login item."
        }
    }
}

enum LoginItemManager {
    private static let preferenceKey = "launchAtLoginDesired"

    static var isDesired: Bool {
        if UserDefaults.standard.object(forKey: preferenceKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: preferenceKey)
    }

    static func state() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    @discardableResult
    static func applyDesiredState() throws -> LoginItemState {
        try setEnabled(isDesired, remember: false)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool, remember: Bool = true) throws -> LoginItemState {
        if remember {
            UserDefaults.standard.set(enabled, forKey: preferenceKey)
        }

        let service = SMAppService.mainApp
        if enabled {
            if service.status == .notFound {
                try? service.unregister()
            }
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
        } else if service.status != .notRegistered {
            try service.unregister()
        }
        return state()
    }

    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
